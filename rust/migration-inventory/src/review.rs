//! Validate explicit source reviews and independent observations.
//! A review is an attestation, not proof that source discovery was complete.

use std::collections::{BTreeMap, BTreeSet};
use crate::{bridge::{validate_snapshot, INVENTORY_LEDGER, OBSERVATION_LEDGER}, snapshot::Snapshot, Entry, Identity, Kind, State};

fn fields(line: &str) -> Vec<&str> { line.split('\t').collect() }
fn present(value: &str) -> bool { !value.trim().is_empty() && !value.chars().any(char::is_control) }

fn kind(value: &str) -> Result<Kind, &'static str> {
    match value {
        "file" => Ok(Kind::File),
        "embedded" => Ok(Kind::Embedded),
        "generated" => Ok(Kind::Generated),
        _ => Err("invalid identity kind"),
    }
}

fn grandfathered_path(path: &str) -> bool {
    ["checkup-read-consumer", "compiler-queue-observer", "connector-credentials", "queue-privacy-cutover"]
        .iter().any(|name| path.starts_with(&format!("tests/fixtures/{name}/")))
}

fn state(value: &str) -> Result<State, &'static str> {
    match value {
        "ported" => Ok(State::Ported),
        "exception" => Ok(State::Exception),
        "frozen" => Ok(State::Frozen),
        "grandfathered" => Ok(State::Grandfathered),
        "out-of-scope" => Ok(State::OutOfScope),
        _ => Err("invalid inventory state"),
    }
}

/// Validate ledgers against one committed snapshot; an empty result is structural only.
pub fn check(snapshot: &Snapshot, observed: &str, manifest: &str) -> Result<(), &'static str> {
    let sources: BTreeMap<_, _> = snapshot.paths.iter()
        .filter(|p| p.path != INVENTORY_LEDGER && p.path != OBSERVATION_LEDGER)
        .map(|p| (p.path.as_str(), p.object.as_str())).collect();
    if sources.len() != snapshot.paths.iter().filter(|p| p.path != INVENTORY_LEDGER && p.path != OBSERVATION_LEDGER).count() {
        return Err("duplicate snapshot path");
    }
    let mut reviews = BTreeSet::new();
    let mut observations = Vec::new();
    for line in observed.lines().filter(|line| !line.is_empty() && !line.starts_with('#')) {
        let f = fields(line);
        match f.as_slice() {
            ["review", path, digest, reviewer, anchor] if present(reviewer) && present(anchor) => {
                if sources.get(path).copied() != Some(*digest) || !reviews.insert(*path) {
                    return Err("invalid, stale, or duplicate source review");
                }
            }
            ["observation", k, path, boundary, digest] if present(boundary) => {
                let k = kind(k)?;
                if matches!(k, Kind::File) { return Err("file observations are derived from Git"); }
                observations.push(Identity { path: (*path).into(), kind: k, boundary: (*boundary).into(), source_digest: (*digest).into() });
            }
            _ => return Err("invalid observation ledger record"),
        }
    }
    if reviews.len() != sources.len() || sources.is_empty() { return Err("source reviews are incomplete"); }
    let mut entries = Vec::new();
    for line in manifest.lines().filter(|line| !line.is_empty() && !line.starts_with('#')) {
        let f = fields(line);
        match f.as_slice() {
            [k, path, boundary, digest, owner, caller, disposition, reason] => {
                let state = state(disposition)?;
                if matches!(state, State::Grandfathered) && !grandfathered_path(path) {
                    return Err("grandfathered state is limited to pre-existing fixture crates");
                }
                entries.push(Entry {
                    identity: Identity { path: (*path).into(), kind: kind(k)?, boundary: (*boundary).into(), source_digest: (*digest).into() },
                    owner: (*owner).into(), caller: (*caller).into(), state,
                    reason: if *reason == "-" { String::new() } else { (*reason).into() },
                });
            }
            _ => return Err("invalid inventory ledger record"),
        }
    }
    if !validate_snapshot(snapshot, &observations, &entries).is_empty() {
        return Err("inventory comparison failed");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::snapshot::TrackedPath;

    fn fixture() -> (Snapshot, String, String) {
        let oid = "a".repeat(40);
        let snapshot = Snapshot { revision: "b".repeat(40), paths: vec![
            TrackedPath { path: "bin/tool".into(), mode: "100755".into(), object: oid.clone() },
        ] };
        let observed = format!("review\tbin/tool\t{oid}\treviewer\tentry and bodies reviewed\nobservation\tembedded\tbin/tool\tpython-body\t{oid}\nobservation\tgenerated\tbin/tool\tgenerated-tool\t{oid}\n");
        let manifest = format!("file\tbin/tool\ttracked-file\t{oid}\tdotfiles\tcli\tported\t-\nembedded\tbin/tool\tpython-body\t{oid}\tdotfiles\tcli\tported\t-\ngenerated\tbin/tool\tgenerated-tool\t{oid}\tdotfiles\tcli\tported\t-\n");
        (snapshot, observed, manifest)
    }

    #[test]
    fn complete_fixture_passes_and_each_manifest_omission_fails() {
        let (snapshot, observed, manifest) = fixture();
        assert!(check(&snapshot, &observed, &manifest).is_ok());
        let lines: Vec<_> = manifest.lines().collect();
        for index in 0..lines.len() {
            let incomplete = lines.iter().enumerate().filter(|(n, _)| *n != index).map(|(_, line)| *line).collect::<Vec<_>>().join("\n");
            assert!(check(&snapshot, &observed, &incomplete).is_err());
        }
    }

    #[test]
    fn rejects_missing_stale_duplicate_and_invalid_records() {
        let (mut snapshot, observed, manifest) = fixture();
        assert!(check(&snapshot, &observed.lines().skip(1).collect::<Vec<_>>().join("\n"), &manifest).is_err());
        assert!(check(&snapshot, &format!("{observed}{}\n", observed.lines().next().unwrap()), &manifest).is_err());
        assert!(check(&snapshot, &observed, &manifest.replace("ported", "unknown")).is_err());
        assert!(check(&snapshot, &observed, &manifest.replace("ported", "grandfathered")).is_err());
        assert!(check(&snapshot, &observed, "malformed").is_err());
        snapshot.paths[0].object = "c".repeat(40);
        assert!(check(&snapshot, &observed, &manifest).is_err());
        snapshot.paths.push(TrackedPath { path: "bin/new-tool".into(), mode: "100755".into(), object: "d".repeat(40) });
        assert!(check(&snapshot, &observed, &manifest).is_err());
    }
}

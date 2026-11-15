//! Bind independent observations and reviewed entries to a committed tree.
//! This cannot prove that the supplied non-file observations are complete.

use std::collections::BTreeMap;

use crate::{snapshot::Snapshot, validate, Entry, Error, Identity, Kind};

#[derive(Debug, Eq, PartialEq)]
pub enum BridgeError {
    DuplicatePath,
    FileObservation,
    UnknownSource,
    StaleSource,
    Comparison(Error),
}

/// Compare all tracked paths and supplied observations with reviewed entries.
/// Callers must obtain the snapshot independently and prove observation coverage.
pub fn validate_snapshot(
    snapshot: &Snapshot,
    observations: &[Identity],
    entries: &[Entry],
) -> Vec<BridgeError> {
    let mut errors = Vec::new();
    let mut sources = BTreeMap::new();
    let mut identities = Vec::new();
    for path in &snapshot.paths {
        if sources.insert(path.path.as_str(), path.object.as_str()).is_some() {
            errors.push(BridgeError::DuplicatePath);
        }
        identities.push(Identity {
            path: path.path.clone(),
            kind: Kind::File,
            boundary: "tracked-file".into(),
            source_digest: path.object.clone(),
        });
    }
    for observation in observations {
        if matches!(observation.kind, Kind::File) {
            errors.push(BridgeError::FileObservation);
        }
        match sources.get(observation.path.as_str()) {
            None => errors.push(BridgeError::UnknownSource),
            Some(object) if *object != observation.source_digest => errors.push(BridgeError::StaleSource),
            Some(_) => {}
        }
        identities.push(observation.clone());
    }
    errors.extend(validate(&identities, entries).into_iter().map(BridgeError::Comparison));
    errors
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{snapshot::TrackedPath, State};

    fn fixture() -> (Snapshot, Vec<Identity>, Vec<Entry>) {
        let object = "a".repeat(40);
        let snapshot = Snapshot { revision: "b".repeat(40), paths: vec![
            TrackedPath { path: "bin/tool".into(), mode: "100755".into(), object: object.clone() },
        ] };
        let observations = vec![
            Identity { path: "bin/tool".into(), kind: Kind::Embedded, boundary: "python-body".into(), source_digest: object.clone() },
            Identity { path: "bin/tool".into(), kind: Kind::Generated, boundary: "generated-tool".into(), source_digest: object.clone() },
        ];
        let mut identities = vec![Identity { path: "bin/tool".into(), kind: Kind::File, boundary: "tracked-file".into(), source_digest: object }];
        identities.extend(observations.clone());
        let entries = identities.into_iter().map(|identity| Entry { identity, owner: "dotfiles".into(), caller: "cli".into(), state: State::Ported, reason: String::new() }).collect();
        (snapshot, observations, entries)
    }

    #[test]
    fn rejects_each_missing_file_embedded_or_generated_entry() {
        let (snapshot, observations, entries) = fixture();
        assert!(validate_snapshot(&snapshot, &observations, &entries).is_empty());
        for index in 0..entries.len() {
            let mut incomplete = entries.clone();
            incomplete.remove(index);
            assert!(validate_snapshot(&snapshot, &observations, &incomplete).iter().any(|error| matches!(error, BridgeError::Comparison(Error::MissingEntry(_)))));
        }
    }

    #[test]
    fn rejects_stale_or_unknown_observation_sources() {
        let (snapshot, mut observations, entries) = fixture();
        observations[0].source_digest = "c".repeat(40);
        assert!(validate_snapshot(&snapshot, &observations, &entries).contains(&BridgeError::StaleSource));
        observations[0].path = "bin/unknown".into();
        assert!(validate_snapshot(&snapshot, &observations, &entries).contains(&BridgeError::UnknownSource));
    }

    #[test]
    fn rejects_an_added_extensionless_path_and_duplicate_tree_path() {
        let (mut snapshot, observations, entries) = fixture();
        snapshot.paths.push(TrackedPath { path: "bin/new-tool".into(), mode: "100755".into(), object: "d".repeat(40) });
        assert!(validate_snapshot(&snapshot, &observations, &entries).iter().any(|error| matches!(error, BridgeError::Comparison(Error::MissingEntry(_)))));
        snapshot.paths.push(snapshot.paths[0].clone());
        assert!(validate_snapshot(&snapshot, &observations, &entries).contains(&BridgeError::DuplicatePath));
    }
}

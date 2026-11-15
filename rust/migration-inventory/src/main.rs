use std::path::Path;
use std::process::{Command, ExitCode};

use dotfiles_migration_inventory::{bridge::{INVENTORY_LEDGER, OBSERVATION_LEDGER}, review, shell_discovery::{scan_committed_shell, FindingKind, Report}, snapshot::{committed_tree, Snapshot}};

fn ledger(root: &Path, snapshot: &Snapshot, path: &str) -> Result<String, &'static str> {
    let entry = snapshot.paths.iter().find(|entry| entry.path == path).ok_or("inventory ledger is missing")?;
    if entry.mode != "100644" { return Err("inventory ledger must be a regular non-executable file"); }
    let output = Command::new("/usr/bin/git").arg("-C").arg(root)
        .args(["cat-file", "blob", &entry.object]).env("GIT_NO_REPLACE_OBJECTS", "1")
        .output().map_err(|_| "cannot read inventory ledger")?;
    if !output.status.success() || output.stdout.len() > 16 * 1024 * 1024 {
        return Err("invalid inventory ledger");
    }
    String::from_utf8(output.stdout).map_err(|_| "inventory ledger is not UTF-8")
}

fn finish(snapshot: &Snapshot, observations: &str, inventory: &str) -> Result<(), &'static str> {
    review::check(snapshot, observations, inventory)?;
    // Do not report a completed inventory before independent discovery exists.
    Err("independent embedded and generated discovery remains incomplete")
}

fn shell_report(revision: &str, path: &str, object: &str, report: &Report) -> serde_json::Value {
    let findings: Vec<_> = report.findings.iter().map(|finding| {
        let kind = match finding.kind {
            FindingKind::Embedded => "embedded",
            FindingKind::GeneratedCandidate => "generated-candidate",
            FindingKind::Unresolved => "unresolved",
        };
        serde_json::json!({"kind": kind, "start": finding.start, "end": finding.end, "category": finding.category})
    }).collect();
    serde_json::json!({"revision": revision, "path": path, "source_object": object, "complete": false, "findings": findings})
}

fn run() -> Result<(), &'static str> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let root = std::env::current_dir().map_err(|_| "cannot find repository root")?;
    match args.as_slice() {
        [command, option] if command == "inventory" && option == "--check" => {
            let snapshot = committed_tree(&root)?;
            let observations = ledger(&root, &snapshot, OBSERVATION_LEDGER)?;
            let inventory = ledger(&root, &snapshot, INVENTORY_LEDGER)?;
            finish(&snapshot, &observations, &inventory)
        }
        [command, option, path, tool_option, tool] if command == "inventory" && option == "--scan-shell" && tool_option == "--shfmt" => {
            let snapshot = committed_tree(&root)?;
            let report = scan_committed_shell(&root, &snapshot, path, Path::new(tool))?;
            let entry = snapshot.paths.iter().find(|entry| entry.path == *path).ok_or("source path not in snapshot")?;
            println!("{}", shell_report(&snapshot.revision, path, &entry.object, &report));
            Ok(())
        }
        _ => Err("usage: migration-check inventory --check | inventory --scan-shell PATH --shfmt ABSOLUTE_PATH"),
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => { eprintln!("inventory: {error}"); ExitCode::from(2) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matching_records_do_not_claim_complete_discovery() {
        use dotfiles_migration_inventory::snapshot::TrackedPath;
        let oid = "a".repeat(40);
        let snapshot = Snapshot { revision: "b".repeat(40), paths: vec![
            TrackedPath { path: "bin/tool".into(), mode: "100755".into(), object: oid.clone() },
        ] };
        let observations = format!("review\tbin/tool\t{oid}\treviewer\tentry reviewed\n");
        let inventory = format!("file\tbin/tool\ttracked-file\t{oid}\tdotfiles\tcli\tported\t-\n");
        assert_eq!(finish(&snapshot, &observations, &inventory), Err("independent embedded and generated discovery remains incomplete"));
    }

    #[test]
    fn missing_ledger_fails_closed() {
        let snapshot = Snapshot { revision: "a".repeat(40), paths: Vec::new() };
        assert!(ledger(Path::new("."), &snapshot, INVENTORY_LEDGER).is_err());
    }
}

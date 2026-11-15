use std::path::Path;
use std::process::{Command, ExitCode};

use dotfiles_migration_inventory::{bridge::{INVENTORY_LEDGER, OBSERVATION_LEDGER}, review, snapshot::{committed_tree, Snapshot}};

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

fn run() -> Result<(), &'static str> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    if args != ["inventory", "--check"] { return Err("usage: migration-check inventory --check"); }
    let root = std::env::current_dir().map_err(|_| "cannot find repository root")?;
    let snapshot = committed_tree(&root)?;
    let observations = ledger(&root, &snapshot, OBSERVATION_LEDGER)?;
    let inventory = ledger(&root, &snapshot, INVENTORY_LEDGER)?;
    review::check(&snapshot, &observations, &inventory)?;
    // Do not report a completed inventory before independent discovery exists.
    Err("independent embedded and generated discovery remains incomplete")
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
    fn missing_ledger_fails_closed() {
        let snapshot = Snapshot { revision: "a".repeat(40), paths: Vec::new() };
        assert!(ledger(Path::new("."), &snapshot, INVENTORY_LEDGER).is_err());
    }
}

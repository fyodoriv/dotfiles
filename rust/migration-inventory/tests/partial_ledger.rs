use std::collections::BTreeSet;
use std::process::Command;

fn lines(path: &std::path::Path, prefix: &str) -> BTreeSet<String> {
    std::fs::read_to_string(path).unwrap().lines()
        .filter(|line| line.starts_with(prefix))
        .map(str::to_owned).collect()
}

#[test]
fn reviewed_ledgers_are_complete_and_discovery_stays_open() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut expected_observed = BTreeSet::new();
    let mut expected_inventory = BTreeSet::new();
    for name in ["rust-shell-cold-boundary-review.json", "rust-shell-tooling-boundary-review.json",
                 "rust-setup-service-boundary-review.json", "rust-plugin-workspace-boundary-review.json",
                 "rust-safety-boundary-review.json", "rust-embedded-discovery-review.json"] {
        let review: serde_json::Value = serde_json::from_slice(&std::fs::read(root.join("docs/plans").join(name)).unwrap()).unwrap();
        for entry in review["entries"].as_array().unwrap() {
            let text = |key| entry[key].as_str().unwrap();
            let boundary = format!("bytes:{}-{}:{}", entry["start"].as_u64().unwrap(), entry["end"].as_u64().unwrap(), text("language"));
            let identity = format!("embedded\t{}\t{}\t{}", text("path"), boundary, text("source_object"));
            assert!(expected_observed.insert(format!("observation\t{identity}")));
            assert!(expected_inventory.insert(format!("{identity}\t{}\t{}\t{}\t{}", text("owner"), text("caller"), text("state"), text("reason"))));
        }
    }
    let observed = lines(&root.join("rust/migration-inventory/observations.tsv"), "observation\t");
    let inventory = lines(&root.join("rust/migration-inventory/inventory.tsv"), "embedded\t");
    assert_eq!(observed, expected_observed);
    assert_eq!(inventory, expected_inventory);
    let mut missing = inventory.clone();
    missing.pop_first();
    assert_ne!(missing, expected_inventory);
    let output = Command::new(env!("CARGO_BIN_EXE_migration-check"))
        .current_dir(&root).args(["inventory", "--check"]).output().unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&output.stderr).contains("independent embedded and generated discovery remains incomplete"));
}

use std::collections::BTreeSet;
use std::process::Command;

#[test]
fn vendor_ledger_matches_reviewed_tree_and_stays_incomplete() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let registry: serde_json::Value = serde_json::from_slice(&std::fs::read(root.join("docs/plans/rust-vendor-ownership-review.json")).unwrap()).unwrap();
    let core: serde_json::Value = serde_json::from_slice(&std::fs::read(root.join("docs/plans/rust-shared-core-ownership-review.json")).unwrap()).unwrap();
    let roots: Vec<_> = registry["packages"].as_array().unwrap().iter().map(|p| p["directory"].as_str().unwrap()).collect();
    let prefix = "rust/migration-inventory/vendor/migration-inventory-core-0.1.0/";
    let output = Command::new("git").current_dir(&root).args(["ls-tree", "-r", "-z", "HEAD", "--", "rust/vendor", prefix]).output().unwrap();
    assert!(output.status.success());
    let mut reviews = BTreeSet::new();
    let mut records = BTreeSet::new();
    for row in output.stdout.split(|b| *b == 0).filter(|row| !row.is_empty()) {
        let split = row.iter().position(|b| *b == b'\t').unwrap();
        let meta = std::str::from_utf8(&row[..split]).unwrap();
        let path = std::str::from_utf8(&row[split + 1..]).unwrap();
        let oid = meta.split_whitespace().nth(2).unwrap();
        let (owner, reason, anchor) = if path.starts_with("rust/vendor/") {
            assert!(roots.iter().any(|directory| path.starts_with(*directory)));
            if path.ends_with("/.cargo-checksum.json") {
                ("dotfiles", "Cargo-generated declarative checksum metadata.", "docs/plans/rust-vendor-ownership-review.json")
            } else {
                ("registry-upstream", "Third-party registry package; upstream owns the source.", "docs/plans/rust-vendor-ownership-review.json")
            }
        } else {
            assert_eq!(core["vendor_files"][path], oid);
            if core["vendor_source"] == path {
                ("agentbrew", "Agentbrew owns the pinned shared-core source.", "docs/plans/rust-shared-core-ownership-review.json")
            } else {
                ("dotfiles", "Vendored dependency metadata; declarative.", "docs/plans/rust-shared-core-ownership-review.json")
            }
        };
        assert!(reviews.insert(format!("review\t{path}\t{oid}\townership-review\t{anchor}")));
        assert!(records.insert(format!("file\t{path}\ttracked-file\t{oid}\t{owner}\toffline Cargo dependency\tout-of-scope\t{reason}")));
    }
    let expected = registry["verified_files"].as_u64().unwrap() as usize + roots.len() + core["vendor_files"].as_object().unwrap().len();
    assert_eq!(reviews.len(), expected);
    let read = |name: &str, kind: &str| -> BTreeSet<String> {
        let data = std::fs::read_to_string(root.join("rust/migration-inventory").join(name)).unwrap();
        let mut rows = BTreeSet::new();
        for line in data.lines().filter(|line| line.starts_with(kind) && (line.contains("\trust/vendor/") || line.contains(&format!("\t{prefix}")))) {
            assert!(rows.insert(line.to_owned()));
        }
        rows
    };
    let actual_reviews = read("observations.tsv", "review\t");
    let actual_records = read("inventory.tsv", "file\t");
    assert_eq!(actual_reviews, reviews);
    assert_eq!(actual_records, records);
    let mut omitted = actual_records.clone();
    omitted.pop_first();
    assert_ne!(omitted, records);
}

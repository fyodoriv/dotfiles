use std::collections::BTreeSet;
use std::process::Command;

#[test]
fn document_ledger_matches_regular_non_shebang_markdown() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let output = Command::new("git").current_dir(&root).args(["ls-tree", "-r", "-z", "HEAD", "--", "docs"]).output().unwrap();
    assert!(output.status.success());
    let mut reviews = BTreeSet::new();
    let mut records = BTreeSet::new();
    for row in output.stdout.split(|byte| *byte == 0).filter(|row| !row.is_empty()) {
        let split = row.iter().position(|byte| *byte == b'\t').unwrap();
        let meta = std::str::from_utf8(&row[..split]).unwrap();
        let path = std::str::from_utf8(&row[split + 1..]).unwrap();
        let parts: Vec<_> = meta.split_whitespace().collect();
        if parts[0] != "100644" || parts[1] != "blob" || !path.ends_with(".md") { continue; }
        let oid = parts[2];
        let blob = Command::new("git").current_dir(&root).args(["cat-file", "blob", oid]).output().unwrap();
        assert!(blob.status.success());
        if blob.stdout.starts_with(b"#!") { continue; }
        assert!(reviews.insert(format!("review\t{path}\t{oid}\tdocumentation-scope-review\tdocs/plans/rust-document-ledger-prediction.md")));
        assert!(records.insert(format!("file\t{path}\ttracked-file\t{oid}\tdotfiles\tdocumentation\tout-of-scope\tRegular non-shebang Markdown documentation.")));
    }
    assert!(!reviews.is_empty());
    let read = |name: &str, kind: &str| -> BTreeSet<String> {
        let data = std::fs::read_to_string(root.join("rust/migration-inventory").join(name)).unwrap();
        let mut rows = BTreeSet::new();
        for line in data.lines().filter(|line| line.starts_with(kind) && line.contains("\tdocs/") && line.contains("\tdocumentation")) {
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

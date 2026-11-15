use std::collections::BTreeSet;
use std::process::Command;

#[test]
fn bats_file_records_match_the_committed_tree() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let output = Command::new("git").current_dir(&root).args(["ls-tree", "-r", "-z", "HEAD", "--", "tests"]).output().unwrap();
    assert!(output.status.success());
    let mut expected = BTreeSet::new();
    for row in output.stdout.split(|byte| *byte == 0).filter(|row| !row.is_empty()) {
        let split = row.iter().position(|byte| *byte == b'\t').unwrap();
        let meta = std::str::from_utf8(&row[..split]).unwrap();
        let path = std::str::from_utf8(&row[split + 1..]).unwrap();
        let parts: Vec<_> = meta.split_whitespace().collect();
        if !matches!(parts[0], "100644" | "100755") || parts[1] != "blob" || !path.ends_with(".bats") { continue; }
        assert!(expected.insert(format!("file\t{path}\ttracked-file\t{}\tdotfiles\tBats test tooling\texception\tTest tooling follows its component; embedded and generated programs remain unreviewed.", parts[2])));
    }
    assert!(!expected.is_empty());
    let inventory = std::fs::read_to_string(root.join("rust/migration-inventory/inventory.tsv")).unwrap();
    let mut actual = BTreeSet::new();
    for line in inventory.lines().filter(|line| line.starts_with("file\ttests/") && line.contains("\tBats test tooling\t")) {
        assert!(actual.insert(line.to_owned()));
    }
    assert_eq!(actual, expected);
    let mut omitted = actual.clone();
    omitted.pop_first();
    assert_ne!(omitted, expected);
}

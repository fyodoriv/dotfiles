use std::collections::BTreeSet;
use std::process::Command;

#[test]
fn cold_boundary_review_matches_the_committed_sources() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let review: serde_json::Value = serde_json::from_slice(
        &std::fs::read(root.join("docs/plans/rust-shell-cold-boundary-review.json")).unwrap(),
    ).unwrap();
    let entries = review["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 41);
    let mut seen = BTreeSet::new();
    for entry in entries {
        let path = entry["path"].as_str().unwrap();
        let object = entry["source_object"].as_str().unwrap();
        let start = entry["start"].as_u64().unwrap() as usize;
        let end = entry["end"].as_u64().unwrap() as usize;
        assert!(path.starts_with(".chezmoiscripts/") || (path.starts_with("modules/") && path.ends_with("/doctor.sh")));
        assert_eq!(entry["owner"], "dotfiles");
        assert_eq!(entry["state"], "exception");
        assert!(entry["reason"].as_str().unwrap().contains("exception"));
        assert!(seen.insert((path.to_owned(), start, end)));
        let actual = Command::new("git").current_dir(&root).args(["rev-parse", &format!("HEAD:{path}")]).output().unwrap();
        assert!(actual.status.success());
        assert_eq!(String::from_utf8(actual.stdout).unwrap().trim(), object);
        let blob = Command::new("git").current_dir(&root).args(["cat-file", "blob", object]).output().unwrap();
        assert!(blob.status.success());
        assert!(start < end && end <= blob.stdout.len());
    }
}

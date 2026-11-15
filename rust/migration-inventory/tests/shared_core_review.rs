use std::collections::BTreeMap;
use std::process::Command;

fn valid(review: &serde_json::Value, paths: &BTreeMap<String, String>, manifest: &str, lock: &str) -> bool {
    let Some(pin) = review["upstream_revision"].as_str() else { return false; };
    let Some(blob) = review["upstream_source_blob"].as_str() else { return false; };
    let Some(source) = review["vendor_source"].as_str() else { return false; };
    let Some(files) = review["vendor_files"].as_object() else { return false; };
    if review["owner"] != "agentbrew" || review["state"] != "out-of-scope"
        || !review["reason"].as_str().is_some_and(|reason| !reason.is_empty())
        || pin.len() != 40 || blob.len() != 40 || paths.len() != files.len()
        || paths.get(source).map(String::as_str) != Some(blob)
        || !manifest.contains(&format!("rev = \"{pin}\""))
        || !lock.contains(&format!("rev={pin}#{pin}")) {
        return false;
    }
    files.iter().all(|(path, expected)| expected.as_str().is_some_and(|oid| paths.get(path).map(String::as_str) == Some(oid)))
}

#[test]
fn shared_core_pin_and_vendor_files_match_the_review() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let review: serde_json::Value = serde_json::from_slice(&std::fs::read(root.join("docs/plans/rust-shared-core-ownership-review.json")).unwrap()).unwrap();
    let prefix = "rust/migration-inventory/vendor/migration-inventory-core-0.1.0/";
    let output = Command::new("git").current_dir(&root).args(["ls-tree", "-r", "-z", "HEAD", "--", prefix]).output().unwrap();
    assert!(output.status.success());
    let mut paths = BTreeMap::new();
    for row in output.stdout.split(|b| *b == 0).filter(|row| !row.is_empty()) {
        let split = row.iter().position(|b| *b == b'\t').unwrap();
        let (meta, path) = (&row[..split], &row[split + 1..]);
        let meta = std::str::from_utf8(meta).unwrap();
        let oid = meta.split_whitespace().nth(2).unwrap();
        assert!(paths.insert(std::str::from_utf8(path).unwrap().to_owned(), oid.to_owned()).is_none());
    }
    let manifest = std::fs::read_to_string(root.join("rust/migration-inventory/Cargo.toml")).unwrap();
    let lock = std::fs::read_to_string(root.join("rust/migration-inventory/Cargo.lock")).unwrap();
    assert!(valid(&review, &paths, &manifest, &lock));
    let mut changed = paths.clone();
    *changed.get_mut(review["vendor_source"].as_str().unwrap()).unwrap() = "planted".into();
    assert!(!valid(&review, &changed, &manifest, &lock));
    assert!(!valid(&review, &paths, &manifest.replace(review["upstream_revision"].as_str().unwrap(), "planted"), &lock));
    changed = paths.clone();
    changed.insert(format!("{prefix}extra"), "planted".into());
    assert!(!valid(&review, &changed, &manifest, &lock));
}

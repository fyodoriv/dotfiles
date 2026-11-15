//! Enumerate committed Git tree paths; this is not executable discovery.

use std::collections::BTreeSet;
use std::path::{Component, Path};
use std::process::Command;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TrackedPath {
    pub path: String,
    pub mode: String,
    pub object: String,
}

#[derive(Debug, Eq, PartialEq)]
pub struct Snapshot {
    pub revision: String,
    pub paths: Vec<TrackedPath>,
}

fn object_id(value: &str) -> bool {
    matches!(value.len(), 40 | 64)
        && value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}

fn parse_tree(raw: &[u8]) -> Result<Vec<TrackedPath>, &'static str> {
    if !raw.is_empty() && raw.last() != Some(&0) {
        return Err("unterminated tree record");
    }
    let mut paths = Vec::new();
    let mut seen = BTreeSet::new();
    if raw.is_empty() { return Ok(paths); }
    for record in raw[..raw.len() - 1].split(|b| *b == 0) {
        let separator = record.iter().position(|b| *b == b'\t').ok_or("invalid tree record")?;
        let (metadata, path) = record.split_at(separator);
        let path = &path[1..];
        let metadata = std::str::from_utf8(metadata).map_err(|_| "invalid metadata")?;
        let path = std::str::from_utf8(path).map_err(|_| "unsupported path encoding")?;
        let mut fields = metadata.split(' ');
        let mode = fields.next().ok_or("missing mode")?;
        let kind = fields.next().ok_or("missing type")?;
        let object = fields.next().ok_or("missing object")?;
        if fields.next().is_some()
            || !matches!((mode, kind), ("100644" | "100755" | "120000", "blob") | ("160000", "commit"))
            || !object_id(object)
            || path.is_empty()
            || !path.split('/').all(|part| !part.is_empty() && part != "." && part != "..")
            || !Path::new(path).components().all(|part| matches!(part, Component::Normal(_)))
            || !seen.insert(path.to_owned())
        {
            return Err("invalid or duplicate tree entry");
        }
        paths.push(TrackedPath { path: path.into(), mode: mode.into(), object: object.into() });
    }
    Ok(paths)
}

fn git(root: &Path, args: &[&str]) -> Result<Vec<u8>, &'static str> {
    // Use the system Git so a repository-local PATH entry cannot supply a program.
    let output = Command::new("/usr/bin/git")
        .arg("-C").arg(root)
        .args(args)
        .env("GIT_NO_REPLACE_OBJECTS", "1")
        .output().map_err(|_| "cannot start git")?;
    if !output.status.success() { return Err("git snapshot failed"); }
    Ok(output.stdout)
}

/// Read one immutable committed tree. Working-tree and untracked changes are not included.
pub fn committed_tree(root: &Path) -> Result<Snapshot, &'static str> {
    let top = git(root, &["rev-parse", "--show-toplevel"])?;
    let top = std::str::from_utf8(&top).map_err(|_| "unsupported repository path")?;
    let top = top.strip_suffix('\n').ok_or("invalid repository path")?;
    let selected = root.canonicalize().map_err(|_| "invalid repository path")?;
    if Path::new(top).canonicalize().map_err(|_| "invalid repository path")? != selected {
        return Err("repository root required");
    }
    let revision = git(root, &["rev-parse", "--verify", "HEAD^{commit}"])?;
    let revision = std::str::from_utf8(&revision).map_err(|_| "invalid revision")?;
    let revision = revision.strip_suffix('\n').ok_or("invalid revision")?;
    if !object_id(revision) { return Err("invalid revision"); }
    let tree = git(root, &["ls-tree", "-r", "-z", "--full-tree", revision])?;
    Ok(Snapshot { revision: revision.into(), paths: parse_tree(&tree)? })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_all_path_kinds_and_rejects_bad_records() {
        let oid = "a".repeat(40);
        let input = format!("100755 blob {oid}\tbin/tool\0\
                             100644 blob {oid}\tscripts/generator.sh\0\
                             120000 blob {oid}\tbin/link\0\
                             100644 blob {oid}\tconfig/template.yaml\0");
        let paths = parse_tree(input.as_bytes()).unwrap();
        assert_eq!(paths.len(), 4);
        assert_eq!(paths[0].path, "bin/tool");
        assert_eq!(paths[2].mode, "120000");
        assert!(parse_tree(&input.as_bytes()[..input.len() - 1]).is_err());
        assert!(parse_tree(format!("100755 blob {oid}\t../tool\0").as_bytes()).is_err());
        assert!(parse_tree(format!("100755 blob {oid}\tbin/tool\0{input}").as_bytes()).is_err());
        let mut bad = format!("100644 blob {oid}\t").into_bytes();
        bad.extend_from_slice(&[0xff, 0]);
        assert!(parse_tree(&bad).is_err());
    }

    #[test]
    fn reads_this_committed_repository_tree() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
        let snapshot = committed_tree(&root).unwrap();
        assert!(snapshot.paths.iter().any(|p| p.path == "bin/dotfiles"));
        assert!(snapshot.paths.iter().any(|p| p.path == "rust/migration-inventory/Cargo.toml"));
    }
}

#![cfg(unix)]

use std::fs::{self, DirBuilder, File, Metadata, OpenOptions};
use std::io::{self, ErrorKind, Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

const LOCK: &str = "dispatch-lock";
const RECEIPT: &str = "staging-receipt";
const ARTIFACT: &str = "fixture-controller";
const OLD: &[u8] = b"Old fixture route";
const ARTIFACT_BODY: &[u8] = b"Inert fixture controller";
const ROUTE_BODY: &[u8] = b"Guarded fixture route";
const ROUTES: [&str; 2] = ["shell-route", "scheduled-route"];
const BEFORE_BOOT: &str = "10000000-0000-0000-0000-00000000000a";
const AFTER_BOOT: &str = "20000000-0000-0000-0000-00000000000b";

fn write_new(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .mode(0o600)
        .open(path)?;
    file.write_all(bytes)?;
    file.sync_all()
}

fn identity(meta: &Metadata) -> io::Result<(u64, u64)> {
    if !meta.is_file() || meta.nlink() != 1 || meta.mode() & 0o7777 != 0o600 {
        return Err(ErrorKind::InvalidData.into());
    }
    Ok((meta.dev(), meta.ino()))
}

fn observe(path: &Path, expected: &[u8]) -> io::Result<(u64, u64)> {
    let named = identity(&fs::symlink_metadata(path)?)?;
    let opened = File::open(path)?;
    if identity(&opened.metadata()?)? != named {
        return Err(ErrorKind::InvalidData.into());
    }
    let mut contents = Vec::new();
    opened
        .take(expected.len() as u64 + 1)
        .read_to_end(&mut contents)?;
    if contents != expected || identity(&fs::symlink_metadata(path)?)? != named {
        return Err(ErrorKind::InvalidData.into());
    }
    Ok(named)
}

struct Dispatch<'a> {
    root: &'a Path,
    owner: File,
}

impl<'a> Dispatch<'a> {
    fn acquire(root: &'a Path) -> io::Result<Self> {
        let owner = OpenOptions::new()
            .read(true)
            .write(true)
            .open(root.join(LOCK))?;
        owner.try_lock().map_err(io::Error::from)?;
        let dispatch = Self { root, owner };
        dispatch.check()?;
        Ok(dispatch)
    }

    fn check(&self) -> io::Result<()> {
        if identity(&self.owner.metadata()?)?
            != identity(&fs::symlink_metadata(self.root.join(LOCK))?)?
        {
            return Err(ErrorKind::InvalidData.into());
        }
        Ok(())
    }

    fn replace_route(&self, route: &str) -> io::Result<()> {
        self.check()?;
        observe(&self.root.join(route), OLD)?;
        let sibling = self.root.join(format!("{route}.next"));
        write_new(&sibling, ROUTE_BODY)?;
        fs::rename(&sibling, self.root.join(route))
    }

    fn receipt_body(&self) -> io::Result<String> {
        self.check()?;
        let (device, inode) = identity(&self.owner.metadata()?)?;
        let (artifact_device, artifact_inode) = observe(&self.root.join(ARTIFACT), ARTIFACT_BODY)?;
        let mut receipt = format!("v1 {BEFORE_BOOT}\nlock {device} {inode}\nartifact {artifact_device} {artifact_inode}\n");
        for route in ROUTES {
            let (device, inode) = observe(&self.root.join(route), ROUTE_BODY)?;
            receipt.push_str(&format!("{route} {device} {inode}\n"));
        }
        Ok(receipt)
    }

    fn publish_receipt(&self) -> io::Result<()> {
        let receipt = self.receipt_body()?;
        if self.root.join(RECEIPT).symlink_metadata().is_ok() {
            return Err(ErrorKind::AlreadyExists.into());
        }
        let staged = self.root.join("receipt.next");
        write_new(&staged, receipt.as_bytes())?;
        self.check()?;
        fs::rename(staged, self.root.join(RECEIPT))
    }

    fn recognize_staged_routes(&self, boot: &str) -> io::Result<()> {
        if boot != AFTER_BOOT {
            return Err(ErrorKind::InvalidData.into());
        }
        let expected = self.receipt_body()?;
        observe(&self.root.join(RECEIPT), expected.as_bytes())?;
        self.check()
    }
}

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "queue-route-stage-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        DirBuilder::new().mode(0o700).create(&path).unwrap();
        write_new(&path.join(LOCK), b"").unwrap();
        write_new(&path.join(ARTIFACT), ARTIFACT_BODY).unwrap();
        for route in ROUTES {
            write_new(&path.join(route), OLD).unwrap();
        }
        Self(path)
    }

    fn staged(&self) -> Dispatch<'_> {
        let dispatch = Dispatch::acquire(&self.0).unwrap();
        for route in ROUTES {
            dispatch.replace_route(route).unwrap();
        }
        dispatch.publish_receipt().unwrap();
        dispatch
    }

    fn snapshot(&self) -> Vec<(String, u64, u64, u32, Vec<u8>)> {
        let mut files: Vec<_> = self
            .0
            .read_dir()
            .unwrap()
            .map(|entry| {
                let entry = entry.unwrap();
                let meta = entry.metadata().unwrap();
                (
                    entry.file_name().into_string().unwrap(),
                    meta.dev(),
                    meta.ino(),
                    meta.mode(),
                    fs::read(entry.path()).unwrap(),
                )
            })
            .collect();
        files.sort();
        files
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn recognizes_complete_staging_only_after_the_boot_changes() {
    let scratch = Scratch::new();
    let dispatch = scratch.staged();
    let before = scratch.snapshot();
    assert!(scratch.0.join(RECEIPT).is_file());
    assert!(dispatch.recognize_staged_routes(BEFORE_BOOT).is_err());
    drop(dispatch);

    let restarted = Dispatch::acquire(&scratch.0).unwrap();
    restarted.recognize_staged_routes(AFTER_BOOT).unwrap();
    assert_eq!(scratch.snapshot(), before);
}

#[test]
fn partial_replacement_cannot_publish_after_restart() {
    let scratch = Scratch::new();
    let dispatch = Dispatch::acquire(&scratch.0).unwrap();
    dispatch.replace_route(ROUTES[0]).unwrap();
    drop(dispatch);

    let before = scratch.snapshot();
    let restarted = Dispatch::acquire(&scratch.0).unwrap();
    assert!(restarted.publish_receipt().is_err());
    assert!(restarted.recognize_staged_routes(AFTER_BOOT).is_err());
    assert!(!scratch.0.join(RECEIPT).exists());
    assert_eq!(scratch.snapshot(), before);
}

#[test]
fn refuses_a_drifted_route_artifact_or_dispatch_lock() {
    for (name, bytes) in [
        (ROUTES[0], ROUTE_BODY),
        (ARTIFACT, b"Changed artifact".as_slice()),
        (LOCK, b"".as_slice()),
    ] {
        let scratch = Scratch::new();
        let dispatch = scratch.staged();
        let changed = scratch.0.join("replacement");
        write_new(&changed, bytes).unwrap();
        fs::rename(changed, scratch.0.join(name)).unwrap();

        let before = scratch.snapshot();
        assert!(dispatch.recognize_staged_routes(AFTER_BOOT).is_err());
        assert_eq!(scratch.snapshot(), before);
    }
}

#[test]
fn refuses_a_busy_dispatch_lock_before_handoff() {
    let scratch = Scratch::new();
    let active = scratch.staged();
    let before = scratch.snapshot();
    let error = Dispatch::acquire(&scratch.0).err().expect("lock is busy");
    assert_eq!(error.kind(), ErrorKind::WouldBlock);
    assert_eq!(scratch.snapshot(), before);
    drop(active);

    let restarted = Dispatch::acquire(&scratch.0).unwrap();
    restarted.recognize_staged_routes(AFTER_BOOT).unwrap();
    assert_eq!(scratch.snapshot(), before);
}

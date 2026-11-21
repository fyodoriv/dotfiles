#![cfg(unix)]

use std::fs::{self, DirBuilder, File, Metadata, OpenOptions};
use std::io::{self, ErrorKind, Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

const LOCK: &str = "dispatch-lock";
const RECEIPT: &str = "staging-receipt";
const ARTIFACT: &str = "fixture-controller";
const ARCHIVE: &str = "shell-route.previous";
const PENDING: &str = "route-restore";
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

fn read_private(path: &Path, limit: usize) -> io::Result<((u64, u64), Vec<u8>)> {
    let named = identity(&fs::symlink_metadata(path)?)?;
    let opened = File::open(path)?;
    if identity(&opened.metadata()?)? != named {
        return Err(ErrorKind::InvalidData.into());
    }
    let mut contents = Vec::new();
    opened.take(limit as u64 + 1).read_to_end(&mut contents)?;
    if contents.len() > limit || identity(&fs::symlink_metadata(path)?)? != named {
        return Err(ErrorKind::InvalidData.into());
    }
    Ok((named, contents))
}

fn observe(path: &Path, expected: &[u8]) -> io::Result<(u64, u64)> {
    let (named, contents) = read_private(path, expected.len())?;
    if contents != expected {
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

    fn stage_route(&self, route: &str) -> io::Result<PathBuf> {
        self.check()?;
        observe(&self.root.join(route), OLD)?;
        let sibling = self.root.join(format!("{route}.next"));
        write_new(&sibling, ROUTE_BODY)?;
        Ok(sibling)
    }

    fn replace_route(&self, route: &str) -> io::Result<()> {
        fs::rename(self.stage_route(route)?, self.root.join(route))
    }

    fn require_uncommitted(&self) -> io::Result<()> {
        match fs::symlink_metadata(self.root.join(RECEIPT)) {
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
            Ok(_) => Err(ErrorKind::AlreadyExists.into()),
        }
    }

    fn pending_context(&self, archived: &Path) -> io::Result<String> {
        self.check()?;
        let (device, inode) = identity(&self.owner.metadata()?)?;
        let mut record = format!("v1 {BEFORE_BOOT}\nlock {device} {inode}\n");
        for (name, path, contents) in [
            (ARTIFACT, self.root.join(ARTIFACT), ARTIFACT_BODY),
            (ROUTES[1], self.root.join(ROUTES[1]), OLD),
            (ARCHIVE, archived.to_path_buf(), OLD),
        ] {
            let (device, inode) = observe(&path, contents)?;
            record.push_str(&format!("{name} {device} {inode}\n"));
        }
        Ok(record)
    }

    fn pending_body(&self, replacement: &Path) -> io::Result<String> {
        let context = self.pending_context(&self.root.join(ARCHIVE))?;
        let (device, inode) = observe(replacement, ROUTE_BODY)?;
        Ok(format!("{context}{} {device} {inode}\n", ROUTES[0]))
    }

    fn verify_restored_route(&self, route: &Path, pending: &Path) -> io::Result<()> {
        let context = self.pending_context(route)?;
        let (_, record) = read_private(pending, 512)?;
        let suffix = std::str::from_utf8(&record)
            .ok()
            .and_then(|record| record.strip_prefix(&context))
            .and_then(|line| line.strip_prefix("shell-route "))
            .and_then(|line| line.strip_suffix('\n'))
            .ok_or(ErrorKind::InvalidData)?;
        let (device, inode) = suffix.split_once(' ').ok_or(ErrorKind::InvalidData)?;
        let device: u64 = device.parse().map_err(|_| ErrorKind::InvalidData)?;
        let inode: u64 = inode.parse().map_err(|_| ErrorKind::InvalidData)?;
        let restored = observe(route, OLD)?;
        // The replaced entry no longer exists. Its record must describe a
        // different file on the same device and use the original format.
        if inode == 0
            || (device, inode) == restored
            || device != restored.0
            || suffix != format!("{device} {inode}")
        {
            return Err(ErrorKind::InvalidData.into());
        }
        Ok(())
    }

    fn stage_first_replacement(&self) -> io::Result<()> {
        self.require_uncommitted()?;
        let replacement = self.stage_route(ROUTES[0])?;
        write_new(&self.root.join(ARCHIVE), OLD)?;
        let record = self.pending_body(&replacement)?;
        write_new(&self.root.join(PENDING), record.as_bytes())?;
        self.check()?;
        fs::rename(replacement, self.root.join(ROUTES[0]))
    }

    fn restore_first_replacement(&self, boot: &str) -> io::Result<()> {
        if boot != BEFORE_BOOT {
            return Err(ErrorKind::InvalidData.into());
        }
        self.require_uncommitted()?;
        let route = self.root.join(ROUTES[0]);
        let archive = self.root.join(ARCHIVE);
        let pending = self.root.join(PENDING);
        match fs::symlink_metadata(&archive) {
            Ok(_) => {
                let record = self.pending_body(&route)?;
                observe(&pending, record.as_bytes())?;
                self.check()?;
                fs::rename(archive, &route)?;
            }
            Err(error) if error.kind() == ErrorKind::NotFound => {
                self.verify_restored_route(&route, &pending)?;
            }
            Err(error) => return Err(error),
        }
        self.check()?;
        fs::remove_file(pending)
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
        self.require_uncommitted()?;
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

#[test]
fn restores_only_the_recorded_partial_replacement_after_restart() {
    let scratch = Scratch::new();
    let dispatch = Dispatch::acquire(&scratch.0).unwrap();
    let second_route = observe(&scratch.0.join(ROUTES[1]), OLD).unwrap();
    let artifact = observe(&scratch.0.join(ARTIFACT), ARTIFACT_BODY).unwrap();
    dispatch.stage_first_replacement().unwrap();
    let archive = observe(&scratch.0.join(ARCHIVE), OLD).unwrap();
    observe(&scratch.0.join(ROUTES[0]), ROUTE_BODY).unwrap();
    drop(dispatch);

    let restarted = Dispatch::acquire(&scratch.0).unwrap();
    restarted.restore_first_replacement(BEFORE_BOOT).unwrap();
    assert_eq!(observe(&scratch.0.join(ROUTES[0]), OLD).unwrap(), archive);
    assert_eq!(
        observe(&scratch.0.join(ROUTES[1]), OLD).unwrap(),
        second_route
    );
    assert_eq!(
        observe(&scratch.0.join(ARTIFACT), ARTIFACT_BODY).unwrap(),
        artifact
    );
    for file in [ARCHIVE, PENDING, RECEIPT] {
        assert!(!scratch.0.join(file).exists());
    }
    let recovered = scratch.snapshot();
    assert!(restarted.restore_first_replacement(BEFORE_BOOT).is_err());
    assert_eq!(scratch.snapshot(), recovered);
}

#[test]
fn retains_the_archive_on_wrong_boot_or_file_drift() {
    for (name, contents, boot) in [
        (ROUTES[0], ROUTE_BODY, BEFORE_BOOT),
        (ARCHIVE, b"Changed archive".as_slice(), BEFORE_BOOT),
        (ROUTES[1], OLD, BEFORE_BOOT),
        (LOCK, b"".as_slice(), BEFORE_BOOT),
        (PENDING, b"Changed journal".as_slice(), BEFORE_BOOT),
        (RECEIPT, b"Final receipt present".as_slice(), BEFORE_BOOT),
        ("", b"".as_slice(), AFTER_BOOT),
    ] {
        let scratch = Scratch::new();
        let dispatch = Dispatch::acquire(&scratch.0).unwrap();
        dispatch.stage_first_replacement().unwrap();
        drop(dispatch);
        if !name.is_empty() {
            let changed = scratch.0.join("replacement");
            write_new(&changed, contents).unwrap();
            fs::rename(changed, scratch.0.join(name)).unwrap();
        }

        let before = scratch.snapshot();
        let restarted = Dispatch::acquire(&scratch.0).unwrap();
        assert!(restarted.restore_first_replacement(boot).is_err(), "{name}");
        assert!(scratch.0.join(ARCHIVE).is_file(), "{name}");
        assert_eq!(scratch.snapshot(), before, "{name}");
    }
}

fn restore_without_cleanup(scratch: &Scratch) {
    let dispatch = Dispatch::acquire(&scratch.0).unwrap();
    dispatch.stage_first_replacement().unwrap();
    fs::rename(scratch.0.join(ARCHIVE), scratch.0.join(ROUTES[0])).unwrap();
}

#[test]
fn finishes_cleanup_when_the_exact_archive_is_already_restored() {
    let scratch = Scratch::new();
    restore_without_cleanup(&scratch);
    let before = scratch.snapshot();
    let pending = before.iter().filter(|file| file.0 == PENDING).count();
    assert_eq!(pending, 1);
    let expected: Vec<_> = before
        .into_iter()
        .filter(|file| file.0 != PENDING)
        .collect();

    let restarted = Dispatch::acquire(&scratch.0).unwrap();
    restarted
        .restore_first_replacement(BEFORE_BOOT)
        .expect("the exact restored route should allow journal cleanup");
    assert_eq!(scratch.snapshot(), expected);
    assert!(restarted.restore_first_replacement(BEFORE_BOOT).is_err());
    assert_eq!(scratch.snapshot(), expected);
}

#[test]
fn retains_the_cleanup_journal_when_the_route_or_context_changes() {
    for (name, contents, boot) in [
        (ROUTES[0], OLD, BEFORE_BOOT),
        (PENDING, b"Changed journal".as_slice(), BEFORE_BOOT),
        ("", b"".as_slice(), AFTER_BOOT),
    ] {
        let scratch = Scratch::new();
        restore_without_cleanup(&scratch);
        if !name.is_empty() {
            let changed = scratch.0.join("replacement");
            write_new(&changed, contents).unwrap();
            fs::rename(changed, scratch.0.join(name)).unwrap();
        }
        let before = scratch.snapshot();
        let restarted = Dispatch::acquire(&scratch.0).unwrap();
        assert!(restarted.restore_first_replacement(boot).is_err(), "{name}");
        assert_eq!(scratch.snapshot(), before, "{name}");
    }
}

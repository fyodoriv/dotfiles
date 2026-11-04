#![cfg(unix)]

use std::fs::{self, DirBuilder, File, OpenOptions};
use std::io::{self, ErrorKind, Read, Write};
use std::os::unix::fs::{symlink, DirBuilderExt, MetadataExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Barrier;

// This writer belongs to a disposable queue. A live queue needs a trusted
// directory and a qualified admission gate before it can use this protocol.
fn advance(dir: &Path) -> io::Result<u64> {
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(dir.join("epoch-serial"))?;
    lock.lock()?;

    let epoch = dir.join("epoch");
    let current = match File::open(&epoch) {
        Ok(file) => read_epoch(file)?,
        Err(error) if error.kind() == ErrorKind::NotFound => 0,
        Err(error) => return Err(error),
    };
    let next = current.checked_add(1).ok_or(ErrorKind::InvalidData)?;
    let staged = dir.join("epoch-next");
    match fs::symlink_metadata(&staged) {
        Ok(meta) => {
            let owner = lock.metadata()?;
            if !meta.is_file()
                || meta.nlink() != 1
                || meta.uid() != owner.uid()
                || meta.dev() != owner.dev()
            {
                return Err(ErrorKind::InvalidData.into());
            }
            fs::remove_file(&staged)?;
        }
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => return Err(error),
    }
    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&staged)?;
    let result = writeln!(file, "{next}").and_then(|()| fs::rename(&staged, &epoch));
    if result.is_err() {
        let _ = fs::remove_file(&staged);
    }
    result.map(|()| next)
}

fn read_epoch(file: File) -> io::Result<u64> {
    let mut text = String::new();
    file.take(22).read_to_string(&mut text)?;
    let digits = text.strip_suffix('\n').ok_or(ErrorKind::InvalidData)?;
    let number = digits.parse::<u64>().map_err(|_| ErrorKind::InvalidData)?;
    if digits != number.to_string() {
        return Err(ErrorKind::InvalidData.into());
    }
    Ok(number)
}

struct Scratch(PathBuf);

impl Scratch {
    fn new() -> Self {
        static NEXT: AtomicUsize = AtomicUsize::new(0);
        let path = std::env::temp_dir().join(format!(
            "queue-epoch-fixture-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        DirBuilder::new().mode(0o700).create(&path).unwrap();
        Self(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

#[test]
fn simultaneous_admissions_receive_distinct_epochs() {
    let scratch = Scratch::new();
    let barrier = Barrier::new(3);
    let dir = &scratch.0;
    let mut epochs = std::thread::scope(|scope| {
        let handles: [_; 3] = std::array::from_fn(|_| {
            scope.spawn(|| {
                barrier.wait();
                advance(dir).unwrap()
            })
        });
        handles.map(|handle| handle.join().unwrap())
    });
    epochs.sort_unstable();
    assert_eq!(epochs, [1, 2, 3]);
    assert_eq!(fs::read_to_string(dir.join("epoch")).unwrap(), "3\n");
}

#[test]
fn interrupted_staging_recovers_from_committed_epoch() {
    let scratch = Scratch::new();
    let dir = &scratch.0;
    fs::write(dir.join("epoch"), b"5\n").unwrap();
    fs::write(dir.join("epoch-next"), b"99\n").unwrap();
    assert_eq!(advance(dir).unwrap(), 6);
    assert_eq!(fs::read_to_string(dir.join("epoch")).unwrap(), "6\n");
    assert!(!dir.join("epoch-next").exists());
}

#[test]
fn recovery_refuses_unexpected_staging_paths() {
    for kind in ["directory", "symlink", "hardlink"] {
        let scratch = Scratch::new();
        let dir = &scratch.0;
        let staged = dir.join("epoch-next");
        let other = dir.join("other");
        fs::write(dir.join("epoch"), b"5\n").unwrap();
        fs::write(&other, b"canary").unwrap();
        match kind {
            "directory" => fs::create_dir(&staged).unwrap(),
            "symlink" => symlink(&other, &staged).unwrap(),
            _ => fs::hard_link(&other, &staged).unwrap(),
        }
        let inode = fs::symlink_metadata(&staged).unwrap().ino();
        assert_eq!(advance(dir).unwrap_err().kind(), ErrorKind::InvalidData);
        assert_eq!(fs::symlink_metadata(&staged).unwrap().ino(), inode);
        assert_eq!(fs::read(&other).unwrap(), b"canary");
        assert_eq!(fs::read(dir.join("epoch")).unwrap(), b"5\n");
    }
}

#[test]
fn malformed_or_exhausted_epoch_never_resets() {
    let scratch = Scratch::new();
    let dir = &scratch.0;
    for value in ["+5\n", "05\n", "5\n\n", "18446744073709551615\n"] {
        fs::write(dir.join("epoch"), value).unwrap();
        assert_eq!(advance(dir).unwrap_err().kind(), ErrorKind::InvalidData);
        assert_eq!(fs::read_to_string(dir.join("epoch")).unwrap(), value);
        assert!(!dir.join("epoch-next").exists());
    }
}

"""Acquire independently audited source bytes without following checkout links.

The caller must separately audit root ancestors, local filesystem and the
commit-to-blob mapping. This bounds bytes, not wall time, and does not claim
crash durability or protection from same-user transient changes.
"""
import hashlib
import os
from pathlib import Path
import stat

from hook_source_snapshot import parse_manifest, read_snapshot

LIMIT = 2_000_000
DIR_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
FILE_FLAGS = os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK


def same_identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_source(root_fd, path, mode):
    parent_name, filename = path.split("/", 1)
    parent_fd = os.open(parent_name, DIR_FLAGS, dir_fd=root_fd)
    try:
        parent_info = os.fstat(parent_fd)
        if (not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != os.geteuid() or
                parent_info.st_mode & 0o022):
            raise ValueError("invalid source directory")
        fd = os.open(filename, FILE_FLAGS, dir_fd=parent_fd)
        try:
            before = os.fstat(fd)
            executable = bool(before.st_mode & 0o111)
            if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.geteuid() or before.st_nlink != 1 or
                    before.st_mode & 0o022 or
                    before.st_size > LIMIT or executable != (mode == "100755")):
                raise ValueError("invalid source file")
            pieces, remaining = [], before.st_size + 1
            while remaining:
                chunk = os.read(fd, min(65536, remaining))
                if not chunk:
                    break
                pieces.append(chunk)
                remaining -= len(chunk)
            data = b"".join(pieces)
            if (len(data) != before.st_size or same_identity(os.fstat(fd)) != same_identity(before) or
                    same_identity(os.stat(filename, dir_fd=parent_fd, follow_symlinks=False)) != same_identity(before)):
                raise ValueError("source changed")
        finally:
            os.close(fd)
        after = os.stat(parent_name, dir_fd=root_fd, follow_symlinks=False)
        if (after.st_dev, after.st_ino, after.st_mode, after.st_uid) != (
                parent_info.st_dev, parent_info.st_ino, parent_info.st_mode, parent_info.st_uid):
            raise ValueError("source directory changed")
        return data, same_identity(before), (parent_info.st_dev, parent_info.st_ino, parent_info.st_mode, parent_info.st_uid)
    finally:
        os.close(parent_fd)


def write_private(dir_fd, name, data):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW
    fd = os.open(name, flags, 0o600, dir_fd=dir_fd)
    try:
        os.fchmod(fd, 0o600)
        pending = memoryview(data)
        while pending:
            count = os.write(fd, pending)
            if count <= 0:
                raise OSError("short write")
            pending = pending[count:]
    finally:
        os.close(fd)


def acquire(run_dir, manifest, run_id, old_revision, candidate_revision, roots, identities, run_identity):
    """Create one private snapshot; a false result is incomplete evidence."""
    fds = []
    try:
        run_dir = Path(run_dir)
        rows = parse_manifest(manifest, run_id, old_revision, candidate_revision)
        if (not run_dir.is_absolute() or rows is None or type(roots) is not dict or set(roots) != {"old", "new"} or
                type(identities) is not dict or set(identities) != {"old", "new"} or
                type(run_identity) is not tuple or len(run_identity) != 2 or
                any(type(value) is not int for value in run_identity)):
            return False
        run_fd = os.open(run_dir, DIR_FLAGS)
        fds.append(run_fd)
        info = os.fstat(run_fd)
        if (info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700 or
                (info.st_dev, info.st_ino) != run_identity):
            return False
        root_fds = {}
        for side in ("old", "new"):
            root = Path(roots[side])
            expected = identities[side]
            if (not root.is_absolute() or type(expected) is not tuple or len(expected) != 2 or
                    any(type(value) is not int for value in expected)):
                return False
            fd = os.open(root, DIR_FLAGS)
            fds.append(fd)
            actual = os.fstat(fd)
            if (actual.st_uid != os.geteuid() or actual.st_mode & 0o022 or
                    (actual.st_dev, actual.st_ino) != expected):
                return False
            root_fds[side] = fd
        contents = []
        for row in rows:
            item = read_source(root_fds[row["side"]], row["path"], row["mode"])
            data = item[0]
            oid = hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data,
                               usedforsecurity=False).hexdigest()
            if oid != row["blob"] or hashlib.sha256(data).hexdigest() != row["sha256"]:
                return False
            contents.append(item)
        os.mkdir("source", 0o700, dir_fd=run_fd)
        dest_fd = os.open("source", DIR_FLAGS, dir_fd=run_fd)
        fds.append(dest_fd)
        os.fchmod(dest_fd, 0o700)
        dest_info = os.fstat(dest_fd)
        for row, item in zip(rows, contents):
            write_private(dest_fd, row["file"], item[0])
        for row, item in zip(rows, contents):
            if read_source(root_fds[row["side"]], row["path"], row["mode"]) != item:
                return False
        for side in ("old", "new"):
            current = os.stat(roots[side], follow_symlinks=False)
            if ((current.st_dev, current.st_ino) != identities[side] or not stat.S_ISDIR(current.st_mode) or
                    current.st_uid != os.geteuid() or current.st_mode & 0o022):
                return False
        current_run = os.stat(run_dir, follow_symlinks=False)
        if ((current_run.st_dev, current_run.st_ino) != run_identity or not stat.S_ISDIR(current_run.st_mode) or
                current_run.st_uid != os.geteuid() or stat.S_IMODE(current_run.st_mode) != 0o700):
            return False
        write_private(dest_fd, "manifest.json", manifest)
        after = os.stat("source", dir_fd=run_fd, follow_symlinks=False)
        if (after.st_dev, after.st_ino, after.st_mode, after.st_uid) != (
                dest_info.st_dev, dest_info.st_ino, dest_info.st_mode, dest_info.st_uid):
            return False
        return read_snapshot(run_dir / "source", manifest, run_id, old_revision, candidate_revision) is not None
    except (KeyError, OSError, TypeError, ValueError):
        return False
    finally:
        for fd in reversed(fds):
            os.close(fd)

"""Preflight controls for a future exclusive hook pair worker."""
from contextlib import ExitStack
import hashlib
import os
import stat
from pathlib import Path
import re

from hook_pair_receipts import private_dir
from hook_rss_provenance import identity
from hook_pair_private import read_private
from hook_source_snapshot import EXPECTED, read_snapshot
from hook_trusted_launch import strict_json

HOOK = "agent-hooks/block-dangerous-git.sh"
BOOTSTRAP = "agent-hooks/bootstrap-endpoint-path.sh"
PARSER = "agent-hooks/plain-document-write.jq"
ENDPOINT = "lib/dotfiles-endpoint-paths.sh"
STATUS = "agent-hooks/literal-status-only.sh"


def identity_ok(root, run_dir, environ, parent_pid):
    try:
        root, run_dir = Path(root), Path(run_dir)
        run_id = environ["HOOK_PAIR_RUN_ID"]
        revisions = [environ[key] for key in ("HOOK_PAIR_CANDIDATE", "HOOK_PAIR_OLD", "HOOK_PAIR_HARNESS_REVISION")]
        audit = environ["HOOK_PAIR_AUDIT_SHA256"]
        source_audit = environ["HOOK_PAIR_SOURCE_AUDIT_SHA256"]
        source_manifest = environ["HOOK_PAIR_MANIFEST_SHA256"]
        mapping = environ["HOOK_PAIR_MAPPING_SHA256"]
        expected_dir = Path(environ["HOME"]) / ".local/state/dotfiles/rust-migration" / ("hook-rss-" + run_id)
        if (not root.is_absolute() or not private_dir(run_dir) or run_dir != expected_dir or
                environ["HOOK_PAIR_RUN_DIR"] != str(run_dir) or environ["DOTFILES_DIR"] != str(root) or
                environ["HEAVY_RUN_SLOT"] != "exclusive" or
                environ["HEAVY_RUN_WAIT_LOG"] != str(run_dir / "wait.log") or
                type(parent_pid) is not int or parent_pid <= 0 or
                type(run_id) is not str or not re.fullmatch(r"[0-9a-f]{32}", run_id) or
                any(type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision) for revision in revisions) or
                any(type(value) is not str or not re.fullmatch(r"[0-9a-f]{64}", value)
                    for value in (audit, source_audit, source_manifest, mapping))):
            return False
        expected = {"format": 1, "run_id": run_id, "candidate_revision": revisions[0],
                    "old_revision": revisions[1], "harness_revision": revisions[2], "audit_sha256": audit,
                    "source_audit_sha256": source_audit, "source_manifest_sha256": source_manifest,
                    "mapping_sha256": mapping}
        intent = strict_json(read_private(run_dir / "intent.json", 4096))
        if type(intent) is not dict or intent != expected or type(intent.get("format")) is not int:
            return False
        if (hashlib.sha256(read_private(run_dir / "mapping.json", 11_000_000)).hexdigest() != mapping or
                read_private(run_dir / "parent", 64) != f"{parent_pid}\n".encode("ascii")):
            return False
        wait = read_private(run_dir / "wait.log", 4096)
        rows = re.findall(rb"\bpid=(\d+)\s+slot=(\S+)", wait)
        return len(wait.splitlines()) == 1 and rows == [(str(parent_pid).encode("ascii"), b"exclusive")]
    except (KeyError, OSError, TypeError, UnicodeError, ValueError):
        return False


def materialize(scratch, old_revision, candidate_revision, fetch):
    """Create equal-layout scratch hooks from already pinned source blobs."""
    scratch = Path(scratch)
    if not private_dir(scratch) or any(scratch.iterdir()):
        raise ValueError("empty private scratch required")
    entries = {}
    for side, revision in (("old", old_revision), ("new", candidate_revision)):
        paths = (HOOK, BOOTSTRAP, PARSER, ENDPOINT) + ((STATUS,) if side == "new" else ())
        for path in paths:
            mode, content = fetch(revision, path)
            expected_mode = "100644" if path in (PARSER, ENDPOINT) else "100755"
            if mode != expected_mode or type(content) is not bytes or len(content) > 2_000_000:
                raise ValueError("invalid source blob")
            entries[(side, path)] = (mode, content)
    if any(entries[("old", path)] != entries[("new", path)] for path in (BOOTSTRAP, PARSER, ENDPOINT)):
        raise ValueError("shared source differs")
    paths = []
    hooks = {}
    for side in ("old", "new"):
        side_dir = scratch / side
        side_dir.mkdir(mode=0o700)
        source = side_dir / "source"
        links = side_dir / "hooks"
        source.mkdir()
        links.mkdir()
        for path in (HOOK, BOOTSTRAP, PARSER) + ((STATUS,) if side == "new" else ()):
            name = Path(path).name
            target = source / name
            target.write_bytes(entries[(side, path)][1])
            target.chmod(0o755 if entries[(side, path)][0] == "100755" else 0o644)
            link = links / name
            link.symlink_to("../source/" + name)
            paths.extend((target, link))
        hooks[side] = links / Path(HOOK).name
    return {"paths": paths, "snapshot": tuple(identity(path) for path in paths), "hooks": hooks}


def fixture_unchanged(fixture):
    try:
        return (type(fixture) is dict and bool(fixture["paths"]) and
                fixture["snapshot"] == tuple(identity(path) for path in fixture["paths"]))
    except (KeyError, OSError, TypeError, ValueError):
        return False


def materialize_verified(root, run_dir, scratch, environ, parent_pid, manifest):
    """Create a fixture only from a privately verified source snapshot."""
    try:
        if (Path(scratch) != Path(run_dir) / "scratch" or
                not identity_ok(root, run_dir, environ, parent_pid) or type(manifest) is not bytes or
                hashlib.sha256(manifest).hexdigest() != environ["HOOK_PAIR_MANIFEST_SHA256"]):
            return None
        old, new = environ["HOOK_PAIR_OLD"], environ["HOOK_PAIR_CANDIDATE"]
        if old == new:
            return None
        data = read_snapshot(Path(run_dir) / "source", manifest, environ["HOOK_PAIR_RUN_ID"], old, new)
        if data is None:
            return None
        modes = {(side, path): mode for side, path, mode in EXPECTED}
        def fetch(revision, path):
            side = "old" if revision == old else "new" if revision == new else None
            return modes[(side, path)], data[(side, path)]
        return materialize_exclusive(Path(run_dir), fetch, old, new)
    except (KeyError, OSError, TypeError, ValueError):
        return None


def materialize_exclusive(run_dir, fetch, old_revision, candidate_revision):
    """Create a private fixture using held directories and exclusive writes."""
    if not private_dir(run_dir):
        raise ValueError("private run required")
    entries = {}
    for side, revision in (("old", old_revision), ("new", candidate_revision)):
        paths = (HOOK, BOOTSTRAP, PARSER, ENDPOINT) + ((STATUS,) if side == "new" else ())
        for path in paths:
            mode, data = fetch(revision, path)
            expected = "100644" if path in (PARSER, ENDPOINT) else "100755"
            if mode != expected or type(data) is not bytes or len(data) > 2_000_000:
                raise ValueError("invalid source blob")
            entries[side, path] = (mode, data)
    if any(entries["old", path] != entries["new", path] for path in (BOOTSTRAP, PARSER, ENDPOINT)):
        raise ValueError("shared source differs")
    directory_flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    paths, hooks, directories, files = [], {}, [], []
    with ExitStack() as stack:
        def hold(fd):
            stack.callback(os.close, fd)
            return fd
        rootfd = hold(os.open(run_dir, directory_flags))
        info = os.fstat(rootfd)
        current = os.stat(run_dir, follow_symlinks=False)
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.geteuid() or
                stat.S_IMODE(info.st_mode) != 0o700 or
                (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino)):
            raise ValueError("run changed")
        os.mkdir("scratch", 0o700, dir_fd=rootfd)
        scratchfd = hold(os.open("scratch", directory_flags, dir_fd=rootfd))
        directories.append((rootfd, "scratch", scratchfd))
        for side in ("old", "new"):
            os.mkdir(side, 0o700, dir_fd=scratchfd)
            sidefd = hold(os.open(side, directory_flags, dir_fd=scratchfd))
            directories.append((scratchfd, side, sidefd))
            for name in ("source", "hooks"):
                os.mkdir(name, 0o700, dir_fd=sidefd)
            sourcefd = hold(os.open("source", directory_flags, dir_fd=sidefd))
            linksfd = hold(os.open("hooks", directory_flags, dir_fd=sidefd))
            directories.extend(((sidefd, "source", sourcefd), (sidefd, "hooks", linksfd)))
            base = run_dir / "scratch" / side
            for path in (HOOK, BOOTSTRAP, PARSER) + ((STATUS,) if side == "new" else ()):
                name = Path(path).name
                mode, data = entries[side, path]
                fd = hold(os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                                  0o600, dir_fd=sourcefd))
                remaining = memoryview(data)
                while remaining:
                    count = os.write(fd, remaining)
                    if count <= 0:
                        raise OSError("short fixture write")
                    remaining = remaining[count:]
                os.fchmod(fd, 0o755 if mode == "100755" else 0o644)
                os.symlink("../source/" + name, name, dir_fd=linksfd)
                files.append((sourcefd, linksfd, name, fd, mode, data))
                paths.extend((base / "source" / name, base / "hooks" / name))
            hooks[side] = base / "hooks" / Path(HOOK).name
        current = os.stat(run_dir, follow_symlinks=False)
        if (info.st_dev, info.st_ino) != (current.st_dev, current.st_ino):
            raise ValueError("run changed")
        def unchanged():
            root_now = os.stat(run_dir, follow_symlinks=False)
            if (not stat.S_ISDIR(root_now.st_mode) or root_now.st_uid != os.geteuid() or
                    stat.S_IMODE(root_now.st_mode) != 0o700 or
                    (info.st_dev, info.st_ino) != (root_now.st_dev, root_now.st_ino)):
                return False
            for parentfd, name, fd in directories:
                held = os.fstat(fd)
                linked = os.stat(name, dir_fd=parentfd, follow_symlinks=False)
                if (not stat.S_ISDIR(held.st_mode) or held.st_uid != os.geteuid() or
                        stat.S_IMODE(held.st_mode) != 0o700 or
                        (held.st_dev, held.st_ino) != (linked.st_dev, linked.st_ino)):
                    return False
            for sourcefd, linksfd, name, fd, mode, data in files:
                held = os.fstat(fd)
                linked = os.stat(name, dir_fd=sourcefd, follow_symlinks=False)
                if (not stat.S_ISREG(held.st_mode) or held.st_uid != os.geteuid() or held.st_nlink != 1 or
                        stat.S_IMODE(held.st_mode) != (0o755 if mode == "100755" else 0o644) or
                        held.st_size != len(data) or (held.st_dev, held.st_ino) != (linked.st_dev, linked.st_ino) or
                        os.pread(fd, len(data) + 1, 0) != data or
                        os.readlink(name, dir_fd=linksfd) != "../source/" + name):
                    return False
            return True
        if not unchanged():
            raise ValueError("fixture changed")
        snapshot = tuple(identity(path) for path in paths)
        if not unchanged():
            raise ValueError("fixture changed")
        return {"paths": paths, "snapshot": snapshot, "hooks": hooks}

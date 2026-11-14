"""Private pre-fetch intent; does not attest network provenance."""
import hashlib
import json
import os
from pathlib import Path
import re
import stat

from hook_pair_private import read_private
from hook_pair_receipts import private_dir
from hook_remote_mapping import API_ROOT, object_id


def expected(identity, run_id, old, candidate):
    if (type(identity) is not tuple or len(identity) != 2 or
            any(type(value) is not int or value <= 0 for value in identity) or
            type(run_id) is not str or re.fullmatch(r"[0-9a-f]{32}", run_id) is None or
            not object_id(old) or not object_id(candidate) or old == candidate):
        raise ValueError("invalid request")
    return {"format": 1, "run_id": run_id, "old_revision": old, "candidate_revision": candidate,
            "directory_dev": identity[0], "directory_ino": identity[1], "origin": API_ROOT,
            "max_calls": 12, "per_record_bytes": 1_000_000, "total_bytes": 8_000_000,
            "inactivity_seconds": 10}


def encode(identity, run_id, old, candidate):
    return json.dumps(expected(identity, run_id, old, candidate), sort_keys=True,
                      separators=(",", ":")).encode("ascii")


def verify(root, identity, run_id, old, candidate, digest):
    try:
        root = Path(root)
        if (not private_dir(root) or type(digest) is not str or
                re.fullmatch(r"[0-9a-f]{64}", digest) is None):
            return False
        before = root.lstat()
        if (before.st_dev, before.st_ino) != identity:
            return False
        raw = read_private(root / "request.json", 4096)
        after = root.lstat()
        return (private_dir(root) and (after.st_dev, after.st_ino) == identity and
                raw == encode(identity, run_id, old, candidate) and hashlib.sha256(raw).hexdigest() == digest)
    except (OSError, TypeError, ValueError):
        return False


def reserve(root, identity, run_id, old, candidate):
    try:
        root = Path(root)
        raw = encode(identity, run_id, old, candidate)
        if not private_dir(root):
            return None
        rootfd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            held = os.fstat(rootfd)
            current = root.lstat()
            if (not stat.S_ISDIR(held.st_mode) or held.st_uid != os.geteuid() or
                    stat.S_IMODE(held.st_mode) != 0o700 or (held.st_dev, held.st_ino) != identity or
                    (current.st_dev, current.st_ino) != identity):
                return None
            fd = os.open("request.json", os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=rootfd)
            try:
                remaining = memoryview(raw)
                while remaining:
                    count = os.write(fd, remaining)
                    if count <= 0:
                        raise OSError("short write")
                    remaining = remaining[count:]
            finally:
                os.close(fd)
        finally:
            os.close(rootfd)
        digest = hashlib.sha256(raw).hexdigest()
        return digest if verify(root, identity, run_id, old, candidate, digest) else None
    except (OSError, TypeError, ValueError):
        return None

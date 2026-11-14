"""Nonblocking, no-follow reads for private pair-timing records."""
import os
from pathlib import Path
import stat


def fingerprint(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_nlink,
            info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def read_private(path, limit=1_000_000):
    path = Path(path)
    if not path.is_absolute() or type(limit) is not int or limit < 0:
        raise ValueError("invalid private read")
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.geteuid() or
                stat.S_IMODE(before.st_mode) != 0o600 or before.st_nlink != 1 or before.st_size > limit):
            raise ValueError("private file required")
        pieces, remaining = [], before.st_size + 1
        while remaining:
            data = os.read(fd, min(65536, remaining))
            if not data:
                break
            pieces.append(data)
            remaining -= len(data)
        result = b"".join(pieces)
        if (len(result) != before.st_size or fingerprint(os.fstat(fd)) != fingerprint(before) or
                fingerprint(os.stat(path, follow_symlinks=False)) != fingerprint(before)):
            raise ValueError("private file changed")
        return result
    finally:
        os.close(fd)


def expected_parent_valid(path, parent):
    try:
        return type(parent) is int and parent > 0 and read_private(path, 64) == f"{parent}\n".encode("ascii")
    except (OSError, TypeError, ValueError):
        return False

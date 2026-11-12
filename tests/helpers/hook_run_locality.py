"""Bind a caller-audited locality check to one held run-directory handle."""
import os
from pathlib import Path
import stat


def check(root, identity, inspect):
    try:
        root = Path(root)
        if (not root.is_absolute() or type(identity) is not tuple or len(identity) != 2 or
                any(type(value) is not int or value <= 0 for value in identity) or not callable(inspect)):
            return False
        fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            def valid():
                held = os.fstat(fd)
                path = root.lstat()
                return (stat.S_ISDIR(held.st_mode) and held.st_uid == os.geteuid() and
                        stat.S_IMODE(held.st_mode) == 0o700 and
                        (held.st_dev, held.st_ino) == identity == (path.st_dev, path.st_ino))
            return valid() and inspect(fd) is True and valid()
        finally:
            os.close(fd)
    except Exception:
        return False

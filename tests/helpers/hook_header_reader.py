"""Prepare header evidence under a caller-audited root; never execute files."""
import hashlib
import os
import re
import stat

from hook_shebang import MAX_HEADER_BYTES, decode_header
from hook_snapshot_acquire import read_source, same_identity

_COMPONENT = re.compile(r"[A-Za-z0-9_.-]+")


def read_header(root_fd, expected_root, relative_path):
    """Return private evidence or None; ancestry and filesystem need separate audit."""
    if (type(root_fd) is not int or type(expected_root) is not tuple or len(expected_root) != 2 or
            any(type(value) is not int for value in expected_root) or type(relative_path) is not str):
        return None
    components = relative_path.split("/")
    if (len(components) != 2 or any(not _COMPONENT.fullmatch(part) or part in (".", "..") for part in components)):
        return None
    try:
        before = os.fstat(root_fd)
        if (not stat.S_ISDIR(before.st_mode) or before.st_uid != os.geteuid() or stat.S_IMODE(before.st_mode) != 0o700 or
                (before.st_dev, before.st_ino) != expected_root):
            return None
        data, file_identity, parent_identity = read_source(root_fd, relative_path, "100755")
        if same_identity(os.fstat(root_fd)) != same_identity(before):
            return None
        header = decode_header(data[:MAX_HEADER_BYTES])
        if header[0] == "unsupported":
            return None
        return {"header": header, "sha256": hashlib.sha256(data).hexdigest(),
                "root_identity": same_identity(before), "parent_identity": parent_identity,
                "file_identity": file_identity}
    except (OSError, ValueError):
        return None

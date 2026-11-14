"""Bind bootstrap's configured root and live endpoint helper at boundaries."""
import os
from pathlib import Path
import stat

from hook_snapshot_acquire import DIR_FLAGS, read_source

ENDPOINT = "lib/dotfiles-endpoint-paths.sh"


def snapshot(root, identity, environ, expected_helper):
    try:
        root = Path(root)
        if (not root.is_absolute() or type(identity) is not tuple or len(identity) != 2 or
                any(type(value) is not int or value <= 0 for value in identity) or
                type(environ) is not dict or environ.get("DOTFILES_DIR") != str(root) or
                type(expected_helper) is not bytes or len(expected_helper) > 2_000_000):
            return None
        root_fd = os.open(root, DIR_FLAGS)
        try:
            base = os.fstat(root_fd)
            if (base.st_uid != os.geteuid() or base.st_mode & 0o022 or
                    (base.st_dev, base.st_ino) != identity):
                return None
            bin_fd = os.open("bin", DIR_FLAGS, dir_fd=root_fd)
            try:
                binary = os.fstat(bin_fd)
                if binary.st_uid != os.geteuid() or binary.st_mode & 0o022:
                    return None
                helper = read_source(root_fd, ENDPOINT, "100644")
                if helper[0] != expected_helper or read_source(root_fd, ENDPOINT, "100644") != helper:
                    return None
                base_after, bin_after = root.lstat(), os.stat("bin", dir_fd=root_fd, follow_symlinks=False)
                root_key = (base.st_dev, base.st_ino, base.st_mode, base.st_uid)
                bin_key = (binary.st_dev, binary.st_ino, binary.st_mode, binary.st_uid)
                if (not stat.S_ISDIR(base_after.st_mode) or not stat.S_ISDIR(bin_after.st_mode) or
                        root_key != (base_after.st_dev, base_after.st_ino, base_after.st_mode, base_after.st_uid) or
                        bin_key != (bin_after.st_dev, bin_after.st_ino, bin_after.st_mode, bin_after.st_uid)):
                    return None
                return root_key, bin_key, helper[1], helper[2]
            finally:
                os.close(bin_fd)
        finally:
            os.close(root_fd)
    except (OSError, TypeError, ValueError):
        return None

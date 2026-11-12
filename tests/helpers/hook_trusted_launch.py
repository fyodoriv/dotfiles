#!/usr/bin/env python3
"""Trusted-launch checks for a private hook memory receipt."""
import hashlib
import os
import re
import stat
import subprocess


def safe_queue_environment(environ):
    return not any(name.startswith("HEAVY_RUN_") and value for name, value in environ.items())


def matches_digest(path, expected):
    try:
        return bool(path.is_absolute() and path.is_file() and re.fullmatch(r"[0-9a-f]{64}", expected) and
                    hashlib.sha256(path.read_bytes()).hexdigest() == expected)
    except OSError:
        return False


def create_private_log(run_dir):
    info = run_dir.lstat()
    if (not run_dir.is_absolute() or not stat.S_ISDIR(info.st_mode) or
            info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError("private directory required")
    log = run_dir / "wait.log"
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    os.close(fd)
    return log


def spawn_with_parent(launcher, command, run_dir, environ, workdir=None):
    parent = run_dir / "parent"
    staging = run_dir / "parent.new"
    if parent.exists() or staging.exists():
        raise FileExistsError("parent record exists")
    process = subprocess.Popen([str(launcher), "--exclusive", *command], cwd=workdir or run_dir,
                               env=environ, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    fd = os.open(staging, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(f"{process.pid}\n")
    os.link(staging, parent)
    staging.unlink()
    return process

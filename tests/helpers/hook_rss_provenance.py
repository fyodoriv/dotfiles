#!/usr/bin/env python3
"""Collect a private, bounded receipt for the registered hook RSS baseline."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

TRACKED = (
    "agent-hooks/block-dangerous-git.sh",
    "agent-hooks/literal-status-only.sh",
    "agent-hooks/bootstrap-endpoint-path.sh",
    ".chezmoiscripts/run_after_agent-hooks.sh",
    "lib/dotfiles-endpoint-paths.sh",
    "bin/heavy-run",
    "tests/helpers/hook_trusted_launch.py",
    "tests/helpers/hook_rss_provenance.py",
)
PAYLOAD = b'{"tool_input":{"command":"git status"},"cwd":"/tmp"}'
HOOK_LINKS = ("block-dangerous-git.sh", "bootstrap-endpoint-path.sh", "literal-status-only.sh")


def admission_valid(text, parent, slot):
    rows = re.findall(r"\bpid=(\d+)\s+slot=(\S+)", text)
    return slot == "exclusive" and rows == [(str(parent), "exclusive")]


def expected_parent_valid(path, parent):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as handle:
            info = os.fstat(handle.fileno())
            return (stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid() and
                    stat.S_IMODE(info.st_mode) == 0o600 and info.st_nlink == 1 and
                    handle.read(32) == (str(parent) + "\n").encode("ascii"))
    except OSError:
        return False


def wait_expected_parent(path, parent, timeout=5):
    deadline = time.monotonic() + timeout
    while True:
        if expected_parent_valid(path, parent):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.01)


def summary(windows, flags, loads, cpus):
    safe_windows = isinstance(windows, list) and len(windows) <= 2 and all(
        isinstance(window, list) and len(window) <= 15 and
        all(type(value) is int and value > 0 for value in window) for window in windows
    )
    samples_ok = safe_windows and len(windows) == 2 and all(len(window) == 15 for window in windows)
    load_ok = type(cpus) is int and cpus > 0 and len(loads) == 4 and all(
        type(value) in (int, float) and 0 <= value <= cpus for value in loads
    )
    valid = samples_ok and load_ok and all(flags.get(key) is True for key in (
        "admission", "source", "harness", "tools", "output"
    ))
    medians = [sorted(window)[7] for window in windows] if samples_ok else []
    ratio = medians[1] / medians[0] if medians else None
    return {
        "valid": valid,
        "samples": windows if safe_windows else [],
        "medians": medians,
        "aa_ratio": ratio,
        "aa_pass": bool(valid and ratio is not None and 0.95 <= ratio <= 1.05),
        "flags": {key: flags.get(key) is True for key in ("admission", "source", "harness", "tools", "output")},
        "load_ok": load_ok,
    }


def identity(path):
    if not path:
        return None
    candidate = Path(path)
    try:
        info = candidate.lstat()
    except FileNotFoundError:
        return (str(candidate), "absent")
    target = os.readlink(candidate) if stat.S_ISLNK(info.st_mode) else ""
    try:
        resolved = candidate.resolve(strict=True)
        final = resolved.stat()
        digest = hashlib.sha256(resolved.read_bytes()).digest() if stat.S_ISREG(final.st_mode) else b""
        return (str(candidate), info.st_mode, info.st_ino, info.st_mtime_ns, info.st_size,
                target, str(resolved), final.st_mode, final.st_ino, final.st_mtime_ns, final.st_size, digest)
    except FileNotFoundError:
        return (str(candidate), info.st_mode, info.st_ino, info.st_mtime_ns, info.st_size, target, "dangling")


def scratch_links_valid(root, links):
    try:
        return all((links / name).is_symlink() and
                   os.readlink(links / name) == str(root / "agent-hooks" / name) and
                   (links / name).is_file() for name in HOOK_LINKS)
    except OSError:
        return False


def source_clean(root, revision):
    for path in TRACKED:
        present = subprocess.run(["git", "cat-file", "-e", f"{revision}:{path}"], cwd=root,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if present.returncode or (root / path).is_symlink() or not (root / path).is_file():
            return False
    result = subprocess.run(["git", "diff", "--quiet", revision, "--", *TRACKED], cwd=root,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return result.returncode == 0


def harness_matches(executing, expected, digest):
    return (executing.resolve() == expected.resolve() and
            bool(re.fullmatch(r"[0-9a-f]{64}", digest)) and
            hashlib.sha256(expected.read_bytes()).hexdigest() == digest)


def startup_chain_valid(decoded, environ):
    startup_vars = [environ.get("BASH_ENV", ""), environ.get("ENV", "")]
    if len(decoded) < 5 or decoded[:2] != startup_vars or decoded[3:5] != startup_vars:
        return False
    for name, path in zip(("BASH_ENV", "ENV"), startup_vars):
        expected = environ.get("HOOK_RSS_" + name + "_SHA256", "")
        if not path or not re.fullmatch(r"[0-9a-f]{64}", expected):
            return False
        if hashlib.sha256(Path(path).read_bytes()).hexdigest() != expected:
            return False
    return True


def tool_snapshot(root):
    if any(name.startswith("BASH_FUNC_") for name in os.environ):
        raise ValueError("exported shell function")
    script = r'''printf '%s\0' "${BASH_ENV:-}" "${ENV:-}" "$PATH"
for n in dirname cat readlink grep rg git chezmoi perl; do p=$(command -v "$n" 2>/dev/null || true); printf '%s\0' "$p"; done
printf '%s\0' "$PATH"
source "$1/agent-hooks/bootstrap-endpoint-path.sh" >/dev/null 2>&1 || exit 2
for n in dirname cat readlink grep rg git chezmoi perl; do p=$(command -v "$n" 2>/dev/null || true); printf '%s\0' "$p"; done
printf '%s\0' "${DOTFILES_JQ:-}" "${DOTFILES_FIND:-}" "${DOTFILES_PYTHON3:-}" "${DOTFILES_PYTHON3_13:-}"
printf '%s\0' "$(dotfiles_resolve_fnm_node_bin "$HOME" 2>/dev/null || true)" "$PATH"
'''
    launcher = 'printf "%s\\0" "${BASH_ENV:-}" "${ENV:-}" "$PATH"; exec /bin/bash -c "$1" _ "$2"'
    result = subprocess.run(["/bin/bash", "-c", launcher, "_", script, str(root)], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, check=False)
    values = result.stdout.split(b"\0")
    if result.returncode or result.stderr or len(values) != 30 or values[-1] != b"":
        raise ValueError("tool selection unavailable")
    decoded = [value.decode("utf-8") for value in values[:-1]]
    if not startup_chain_valid(decoded, os.environ):
        raise ValueError("startup chain unavailable or changed")
    selected = decoded[6:14] + decoded[15:27]
    if any(path and not os.path.isabs(path) for path in selected):
        raise ValueError("non-absolute tool selection")
    home = Path(os.environ["HOME"])
    candidates = [root / "bin" / name for name in ("jq", "find", "python3", "python3.13")]
    candidates += [home / ".local/bin" / name for name in ("jq", "find", "python3", "python3.13")]
    candidates += [Path(p) for p in ("/opt/homebrew/bin/gfind", "/usr/local/bin/gfind",
                  "/opt/homebrew/opt/findutils/libexec/gnubin/find", "/usr/local/opt/findutils/libexec/gnubin/find",
                  "/opt/homebrew/bin/jq", "/usr/local/bin/jq")]
    startup = [os.environ.get("BASH_ENV", ""), os.environ.get("ENV", "")]
    fixed = ["/bin/bash", "/usr/bin/time", "/usr/bin/plutil", "/usr/bin/file", sys.executable,
             shutil.which("git"), shutil.which("chezmoi")]
    if any(not path or not Path(path).is_file() for path in fixed):
        raise ValueError("required tool unavailable")
    if any(path and (not os.path.isabs(path) or not Path(path).is_file()) for path in startup + selected):
        raise ValueError("selected tool or startup file unavailable")
    return (tuple(identity(p) for p in fixed + startup + selected + [decoded[27]] + [str(p) for p in candidates]),
            identity(home / ".node-version"), decoded[2], decoded[5], decoded[14], decoded[28],
            tuple(sorted(os.environ.items())))


def installed_root(root):
    git_dir = subprocess.run(["git", "rev-parse", "--absolute-git-dir"], cwd=root, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, check=False)
    source_dir = subprocess.run(["chezmoi", "source-path"], cwd=root, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=False)
    git_value, source_value = git_dir.stdout.decode().strip(), source_dir.stdout.decode().strip()
    return bool(not git_dir.returncode and not source_dir.returncode and git_value and source_value and
                (root / ".git").is_dir() and Path(git_value).resolve() == (root / ".git").resolve() and
                Path(source_value).resolve() == root)


def collect(root, revision, expected_digest, run_id, wait_log, executing=None):
    if (not re.fullmatch(r"[0-9a-f]{32}", run_id) or
            not re.fullmatch(r"[0-9a-f]{64}", expected_digest) or
            not re.fullmatch(r"[0-9a-f]{40}", revision)):
        raise ValueError("invalid run identity")
    harness = root / TRACKED[-1]
    executing = Path(__file__) if executing is None else executing
    harness_before = harness_matches(executing, harness, expected_digest)
    admitted = admission_valid(wait_log.read_text(), os.getppid(), os.environ.get("HEAVY_RUN_SLOT", ""))
    before_source = source_clean(root, revision)
    before_tools = tool_snapshot(root)
    windows, loads = [], []
    output_ok = True
    links_ok = False
    failure = None
    cpus = os.cpu_count()
    if not admitted or not before_source or not harness_before:
        receipt = summary([], {"admission": admitted}, [], cpus)
        receipt["run_id"] = run_id
        receipt["failure"] = {"class": "preflight"}
        return receipt
    window_index, sample_index = 0, 0
    try:
        with tempfile.TemporaryDirectory(prefix="hook-rss-") as scratch:
            links = Path(scratch) / "hooks"
            links.mkdir()
            for name in HOOK_LINKS:
                (links / name).symlink_to(root / "agent-hooks" / name)
            link_before = tuple(identity(links / name) for name in HOOK_LINKS)
            if not scratch_links_valid(root, links):
                raise ValueError("invalid scratch hook links")
            for window_index in range(2):
                sample_index = 0
                loads.append(os.getloadavg()[0])
                if not cpus or loads[-1] > cpus:
                    failure = {"class": "load", "window": window_index, "index": 0}
                    break
                window = []
                windows.append(window)
                for sample_index in range(15):
                    stderr_path = Path(scratch) / "hook-stderr"
                    result = subprocess.run(["/usr/bin/time", "-l", "/bin/bash", "-c", 'exec "$1" 2>"$2"',
                                             "_", str(root / TRACKED[0]), str(stderr_path)], input=PAYLOAD,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
                    match = re.search(rb"^\s*(\d+)\s+maximum resident set size", result.stderr, re.M)
                    hook_error_empty = stderr_path.exists() and stderr_path.stat().st_size == 0
                    reason = ("exit" if result.returncode else "stdout" if result.stdout else
                              "stderr" if not hook_error_empty else "rss" if not match or int(match.group(1)) <= 0 else "")
                    if reason:
                        output_ok = False
                        failure = {"class": reason, "window": window_index, "index": sample_index}
                        break
                    window.append(int(match.group(1)))
                loads.append(os.getloadavg()[0])
                if cpus and loads[-1] > cpus:
                    failure = failure or {"class": "load", "window": window_index, "index": len(window)}
                    break
                if not output_ok:
                    break
            links_ok = (scratch_links_valid(root, links) and
                        link_before == tuple(identity(links / name) for name in HOOK_LINKS))
    except (OSError, ValueError, subprocess.SubprocessError):
        output_ok = False
        failure = failure or {"class": "observation", "window": window_index, "index": sample_index}
    flags = {"admission": admitted, "source": False, "harness": False, "tools": False, "output": output_ok}
    try:
        flags["source"] = before_source and links_ok and source_clean(root, revision) and installed_root(root)
        flags["harness"] = harness_before and harness_matches(executing, harness, expected_digest)
        flags["tools"] = before_tools == tool_snapshot(root)
    except (OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        failure = failure or {"class": "postflight"}
    receipt = summary(windows, flags, loads, cpus)
    receipt["run_id"] = run_id
    receipt["failure"] = failure
    return receipt


def main():
    root = Path.cwd().resolve()
    run_dir = Path(os.environ["HOOK_RSS_RUN_DIR"])
    info = run_dir.lstat()
    if (not run_dir.is_absolute() or not stat.S_ISDIR(info.st_mode) or
            info.st_uid != os.geteuid() or stat.S_IMODE(info.st_mode) != 0o700):
        raise ValueError("private run directory required")
    if run_dir.is_symlink() or os.environ.get("DOTFILES_DIR") != str(root):
        raise ValueError("installed checkout not bound")
    if not installed_root(root):
        raise ValueError("installed checkout not verified")
    parent_file = run_dir / "parent"
    if not wait_expected_parent(parent_file, os.getppid()):
        raise ValueError("trusted parent not bound")
    wait_log = run_dir / "wait.log"
    if os.environ.get("HEAVY_RUN_WAIT_LOG") != str(wait_log):
        raise ValueError("private admission log not bound")
    log_info = wait_log.lstat()
    if (not stat.S_ISREG(log_info.st_mode) or log_info.st_uid != os.geteuid() or
            stat.S_IMODE(log_info.st_mode) != 0o600 or log_info.st_nlink != 1):
        raise ValueError("private admission log required")
    try:
        receipt = collect(root, os.environ["HOOK_RSS_REVISION"], os.environ["HOOK_RSS_HARNESS_SHA256"],
                          os.environ["HOOK_RSS_RUN_ID"], wait_log)
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        receipt = {"valid": False, "aa_pass": False, "failure": {"class": "observation"}}
    target = run_dir / "receipt.json"
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as handle:
        json.dump(receipt, handle, sort_keys=True)
        handle.write("\n")
    print("hook RSS receipt: " + ("valid" if receipt["valid"] else "inconclusive"))
    return 0 if receipt["valid"] and receipt["aa_pass"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, OSError, UnicodeError, ValueError, subprocess.SubprocessError):
        print("hook RSS receipt: inconclusive", file=sys.stderr)
        raise SystemExit(1)

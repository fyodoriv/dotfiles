#!/usr/bin/env python3
"""Check the bounded ownership record without executing vendored code."""
import copy
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[2]
REVIEW = ROOT / "docs/plans/rust-vendor-ownership-review.json"


def matches(expected_packages, actual_packages, expected_files, actual_files):
    return expected_packages == actual_packages and expected_files == actual_files


def controls():
    packages = {"crate": {"digest": "package"}}
    files = {"crate/file": "source"}
    assert matches(packages, packages, files, files)
    changed = copy.deepcopy(packages)
    changed["crate"]["digest"] = "planted"
    assert not matches(packages, changed, files, files)
    assert not matches(packages, packages, files, {"crate/file": "planted"})
    assert not matches(packages, packages, files, {**files, "crate/extra": "source"})


def check():
    review = json.loads(REVIEW.read_text())
    tree = subprocess.check_output(["git", "rev-parse", "HEAD:rust/vendor"], cwd=ROOT, text=True).strip()
    if tree != review["vendor_tree"]:
        raise ValueError("vendor tree changed; review ownership again")
    packages = {}
    for name in ("app-priority", "hook-status", "migration-inventory"):
        lock = tomllib.loads((ROOT / "rust" / name / "Cargo.lock").read_text())
        for package in lock["package"]:
            if package.get("source", "").startswith("registry+"):
                key = (package["name"], package["version"])
                checksum = package["checksum"]
                if key in packages and packages[key] != checksum:
                    raise ValueError("conflicting lockfile checksums")
                packages[key] = checksum
    expected_packages = {}
    for entry in review["packages"]:
        if entry["owner"] != "registry upstream" or entry["state"] != "out-of-scope" or not entry["reason"]:
            raise ValueError("invalid vendor ownership")
        directory = entry["directory"].rstrip("/")
        if directory in expected_packages:
            raise ValueError("duplicate vendor package")
        expected_packages[directory] = {key: entry[key] for key in ("package", "version", "registry_checksum", "files")}
    actual_packages, expected_files, actual_files = {}, {}, {}
    for directory in sorted((ROOT / "rust/vendor").iterdir()):
        if not directory.is_dir() or directory.is_symlink():
            raise ValueError("unexpected vendor entry")
        relative = directory.relative_to(ROOT).as_posix()
        manifest = tomllib.loads((directory / "Cargo.toml").read_text())["package"]
        checksum = json.loads((directory / ".cargo-checksum.json").read_text())
        key = (manifest["name"], manifest["version"])
        registry = packages.get(key)
        if registry is None or registry != checksum["package"]:
            raise ValueError("vendor package does not match lockfile")
        actual_packages[relative] = {"package": key[0], "version": key[1], "registry_checksum": registry, "files": len(checksum["files"])}
        for name, digest in checksum["files"].items():
            part = PurePosixPath(name)
            if part.is_absolute() or ".." in part.parts:
                raise ValueError("invalid vendor file path")
            file = directory.joinpath(*part.parts)
            if not file.is_file() or file.is_symlink():
                raise ValueError("missing or symlinked vendor file")
            path = file.relative_to(ROOT).as_posix()
            expected_files[path] = digest
            actual_files[path] = hashlib.sha256(file.read_bytes()).hexdigest()
    tracked = subprocess.check_output(["git", "ls-files", "-z", "--", "rust/vendor"], cwd=ROOT).split(b"\0")
    tracked = {path.decode() for path in tracked if path}
    listed = set(expected_files) | {directory + "/.cargo-checksum.json" for directory in actual_packages}
    untracked = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z", "--", "rust/vendor"], cwd=ROOT)
    if tracked != listed or untracked or not matches(expected_packages, actual_packages, expected_files, actual_files):
        raise ValueError("vendor ownership or file identity mismatch")
    if len(expected_files) != review["verified_files"]:
        raise ValueError("vendor review file count changed")
    print("vendor ownership and file identities match")


if __name__ == "__main__":
    if sys.argv[1:] != ["--check"]:
        raise SystemExit("usage: rust-vendor-ownership-review.py --check")
    controls()
    check()

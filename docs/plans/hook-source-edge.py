#!/usr/bin/env python3
"""Verify a pinned launcher-to-memory-harness source relationship."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "d6c7b6dd8636a11a140bf3937cdce547377f2e5e"
OUTPUT = Path("docs/plans/hook-source-edge.json")
HARNESS = "tests/helpers/hook_rss_provenance.py"
LAUNCHER = "tests/helpers/hook_trusted_launch.py"
ANCHORS = {
    156: '    harness = root / "tests/helpers/hook_rss_provenance.py"',
    164: '        spec = importlib.util.spec_from_file_location("hook_rss_provenance", harness)',
    165: '        provenance = importlib.util.module_from_spec(spec)',
    166: '        spec.loader.exec_module(provenance)',
    185: '        process, status = launch_and_wait(launcher, [sys.executable, str(harness)], run_dir, child_env, root)',
}


def anchors_match(lines):
    return type(lines) is list and all(number <= len(lines) and lines[number - 1] == text
                                       for number, text in ANCHORS.items())


def generate():
    refs = strict_json(subprocess.check_output(["git", "show", f"{PIN}:docs/plans/test-source-references.json"]))
    revision = refs["candidate_revision"]
    rows = {row["path"]: row for row in refs["records"]}
    if {"file": LAUNCHER, "line": 156} not in rows[HARNESS]["references"]:
        raise ValueError("assignment not in reference receipt")
    tree = {}
    for item in subprocess.check_output(["git", "ls-tree", "-z", revision, "--", HARNESS, LAUNCHER]).split(b"\0"):
        if item:
            meta, path = item.split(b"\t", 1)
            mode, kind, blob = meta.decode("ascii").split()
            if kind != "blob": raise ValueError("non-blob source")
            tree[path.decode("utf-8")] = (mode, blob)
    if any(tree.get(path) != (rows[path]["mode"], rows[path]["blob"]) for path in (HARNESS, LAUNCHER)):
        raise ValueError("source identity changed")
    lines = subprocess.check_output(["git", "show", f"{revision}:{LAUNCHER}"]).decode("utf-8").splitlines()
    if not anchors_match(lines): raise ValueError("source relationship changed")
    return {"format": 1, "pin": PIN, "candidate_revision": revision,
            "caller": {"path": LAUNCHER, "mode": rows[LAUNCHER]["mode"], "blob": rows[LAUNCHER]["blob"]},
            "target": {"path": HARNESS, "mode": rows[HARNESS]["mode"], "blob": rows[HARNESS]["blob"]},
            "anchors": list(ANCHORS), "relationship": "dynamic_import_and_launch"}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: hook-source-edge.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("hook source edge differs from pinned sources")
    print("checked one pinned launcher-to-harness source relationship")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check pinned source declarations for the host-load test helper."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

REVISION = "94eef660b9d531b401f1f78c7c788101eb3e7bfb"
PATH = "tests/host-load.bash"
IDENTITY = ("100644", "c7863c179266fe72a1a08e6811499a8edf41ffe6")
ANCHORS = {
    "tests/agent-keepawake.bats": {9: 'source "$BATS_TEST_DIRNAME/host-load.bash"'},
    "tests/brew-audit.bats": {9: 'source "$BATS_TEST_DIRNAME/host-load.bash"'},
    "tests/test_helper.bash": {75: 'source "${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}/host-load.bash"'},
}
RECEIPT = Path("docs/plans/host-load-relationships.json")


def validate(identity, sources):
    if identity != IDENTITY:
        raise ValueError("helper identity mismatch")
    for path, anchors in ANCHORS.items():
        lines = sources[path].splitlines()
        for line, expected in anchors.items():
            if line > len(lines) or lines[line - 1] != expected:
                raise ValueError("source anchor mismatch")
    return {"revision": REVISION, "path": PATH, "mode": IDENTITY[0], "blob": IDENTITY[1],
            "direct_sources": [{"file": p, "line": 9} for p in list(ANCHORS)[:2]],
            "conditional_path_source": {"file": "tests/test_helper.bash", "line": 75},
            "limits": "runtime test directory and shell fallback affect resolution; no execution or complete caller coverage inferred"}


def snapshot():
    entry = subprocess.check_output(["git", "ls-tree", REVISION, "--", PATH], text=True).strip()
    metadata, actual = entry.split("\t", 1)
    mode, kind, blob = metadata.split()
    if kind != "blob" or actual != PATH:
        raise ValueError("unexpected helper tree entry")
    sources = {p: subprocess.check_output(["git", "show", f"{REVISION}:{p}"], text=True) for p in ANCHORS}
    return (mode, blob), sources


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: host-load-relationships.py --generate|--check")
    result = validate(*snapshot())
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
    elif not same_json(strict_json(RECEIPT.read_text()), result):
        raise SystemExit("host-load receipt differs from pinned source")
    else:
        print("checked 3 source declarations, including 1 conditional path")


if __name__ == "__main__":
    main()

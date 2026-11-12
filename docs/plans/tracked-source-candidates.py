#!/usr/bin/env python3
"""Index tracked paths matching explicitly bounded source predicates."""
import json
from pathlib import Path
import subprocess
import sys

REVISION = "94eef660b9d531b401f1f78c7c788101eb3e7bfb"
RECEIPT = Path("docs/plans/tracked-source-candidates.json")
SUFFIXES = {".sh", ".bash", ".zsh", ".py", ".pl", ".awk", ".rs", ".swift", ".mjs", ".cjs", ".js", ".ts", ".tsx", ".bats", ".tmpl"}


def generate():
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION])
    tree = {}
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind == "blob":
            tree[raw_path.decode("utf-8")] = {"mode": mode, "blob": blob}
    result = subprocess.run(["git", "grep", "-I", "-n", "-z", "-e", "^#!", REVISION, "--"],
                            stdout=subprocess.PIPE, check=False)
    if result.returncode not in (0, 1):
        raise ValueError("shebang search failed")
    remaining, shebangs = result.stdout, set()
    prefix = (REVISION + ":").encode("ascii")
    while remaining:
        raw_path, remaining = remaining.split(b"\0", 1)
        raw_line, remaining = remaining.split(b"\0", 1)
        _text, remaining = remaining.split(b"\n", 1)
        if not raw_path.startswith(prefix):
            raise ValueError("unexpected search revision")
        path = raw_path[len(prefix):].decode("utf-8")
        if path not in tree:
            raise ValueError("search path absent from tree")
        if raw_line == b"1":
            shebangs.add(path)
    files = []
    for path, identity in tree.items():
        reasons = []
        if identity["mode"] == "100755":
            reasons.append("executable-mode")
        if Path(path).suffix in SUFFIXES:
            reasons.append("source-suffix")
        if path in shebangs:
            reasons.append("first-line-shebang")
        if reasons:
            files.append({"path": path, **identity, "reasons": reasons})
    return {"format": 1, "revision": REVISION, "files": files}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: tracked-source-candidates.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print('{\n  "format": 1,')
        print(f'  "revision": {json.dumps(REVISION)},')
        print('  "files": [')
        for index, row in enumerate(expected["files"]):
            suffix = "," if index + 1 < len(expected["files"]) else ""
            print(f"    {json.dumps(row)}{suffix}")
        print('  ]\n}')
        return
    receipt = json.loads(RECEIPT.read_text())
    if receipt != expected:
        raise SystemExit("candidate index does not match pinned sources")
    rows = receipt["files"]
    expected_rows = expected["files"]
    count = 0
    for index, row in enumerate(rows):
        for changed in (rows[:index] + rows[index + 1:], rows + [row],
                        rows[:index] + [{**row, "blob": "planted"}] + rows[index + 1:]):
            if changed == expected_rows:
                raise SystemExit("a planted error was accepted")
            count += 1
    print(f"checked {len(rows)} candidates; rejected {count} planted errors")


if __name__ == "__main__":
    main()

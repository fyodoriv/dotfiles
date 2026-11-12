#!/usr/bin/env python3
"""Record lexical Bats discovery candidates at a pinned revision."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "e5923cea4d3f37324abc169501eccefe382d82a7"
OUTPUT = Path("docs/plans/bats-discovery-receipt.json")


def git(*args):
    return subprocess.check_output(["git", *args])


def generate():
    joined = strict_json(git("show", f"{PIN}:docs/plans/source-evidence-join.json"))
    revision = joined["candidate_revision"]
    makefile = git("show", f"{revision}:Makefile").decode("utf-8").splitlines()
    if (makefile[109] != "BATS_ALL_FILES := $(wildcard tests/*.bats tests/plugin/*.bats)" or
            makefile[192] != "E2E_FILES = $(wildcard tests/e2e/*.bats)" or
            makefile[194] != "\t@bats tests/e2e/"):
        raise ValueError("pinned discovery declarations changed")
    rows = [r for r in joined["candidates"] if r["status"] == "absent" and r["path"].startswith("tests/")]
    if len(rows) != 383 or len({r["path"] for r in rows}) != 383:
        raise ValueError("unexpected or duplicate candidate set")
    tree = {}
    for entry in git("ls-tree", "-r", "-z", revision, "--", "tests/").split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind != "blob":
            raise ValueError("non-blob test tree entry")
        tree[path.decode("utf-8")] = (mode, blob)
    records = []
    for row in rows:
        path = row["path"]
        if tree.get(path) != (row["mode"], row["blob"]):
            raise ValueError("candidate identity mismatch")
        parts = path.split("/")
        is_bats = path.endswith(".bats")
        if is_bats and ((len(parts) == 2) or (len(parts) == 3 and parts[1] == "plugin")):
            discovery = "root_or_plugin_glob"
        elif is_bats and len(parts) == 3 and parts[1] == "e2e":
            discovery = "e2e_glob"
        else:
            discovery = "unresolved"
        records.append({"path": path, "mode": row["mode"], "blob": row["blob"], "discovery": discovery})
    counts = {key: sum(r["discovery"] == key for r in records)
              for key in ("root_or_plugin_glob", "e2e_glob", "unresolved")}
    if counts != {"root_or_plugin_glob": 341, "e2e_glob": 2, "unresolved": 40}:
        raise ValueError("unexpected discovery counts")
    return {"format": 1, "pin": PIN, "candidate_revision": revision,
            "makefile_lines": [110, 193, 195], "counts": counts, "records": records}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: bats-discovery-receipt.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    actual = strict_json(OUTPUT.read_text())
    if not same_json(actual, expected):
        raise SystemExit("receipt differs from pinned sources")
    count = 0
    for index, row in enumerate(expected["records"]):
        for field in ("remove", "duplicate", "path", "mode", "blob", "discovery"):
            if field == "remove":
                changed = expected["records"][:index] + expected["records"][index + 1:]
            elif field == "duplicate":
                changed = expected["records"] + [row]
            else:
                changed = expected["records"][:index] + [{**row, field: "planted"}] + expected["records"][index + 1:]
            if same_json(changed, expected["records"]):
                raise SystemExit("a planted error was accepted")
            count += 1
    print(f"checked {len(actual['records'])} candidates; rejected {count} planted errors")


if __name__ == "__main__":
    main()

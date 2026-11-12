#!/usr/bin/env python3
"""Record changed lifecycle source ranges without copying source text."""
import difflib
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json
from git_blob_batch import read_blobs

PIN = "ac38709703dc51b8e34e62728dccdcad6f9d83e3"
OUTPUT = Path("docs/plans/stale-lifecycle-ranges.json")
PATHS = (
    ".chezmoiscripts/run_after_claude-settings-env.sh",
    ".chezmoiscripts/run_onchange_brew.sh.tmpl",
    ".chezmoiscripts/run_onchange_launchagents.sh.tmpl",
)


def git(*args):
    return subprocess.check_output(["git", *args])


def tree(revision):
    result = {}
    for entry in git("ls-tree", "-r", "-z", revision, "--", *PATHS).split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        path = raw_path.decode("utf-8")
        if kind != "blob" or path in result:
            raise ValueError("invalid source identity")
        result[path] = {"mode": mode, "blob": blob}
    if set(result) != set(PATHS):
        raise ValueError("missing source identity")
    return result


def generate():
    ledger = strict_json(git("show", f"{PIN}:docs/plans/rust-source-inventory-evidence.json"))
    joined = strict_json(git("show", f"{PIN}:docs/plans/source-evidence-join.json"))
    old_revision, current_revision = ledger["revision"], joined["candidate_revision"]
    old_tree, current_tree = tree(old_revision), tree(current_revision)
    ledger_rows = [row for row in ledger["files"].values() if row.get("source_path") in PATHS]
    candidates = [row for row in joined["candidates"] if row.get("path") in PATHS]
    if len(ledger_rows) != 3 or len(candidates) != 3:
        raise ValueError("ambiguous source records")
    old_by_path = {row["source_path"]: row for row in ledger_rows}
    current_by_path = {row["path"]: row for row in candidates}
    if set(old_by_path) != set(PATHS) or set(current_by_path) != set(PATHS):
        raise ValueError("duplicate source records")
    for path in PATHS:
        if (old_by_path[path]["git_blob"] != old_tree[path]["blob"] or
                current_by_path[path]["blob"] != current_tree[path]["blob"] or
                current_by_path[path]["mode"] != current_tree[path]["mode"] or
                current_by_path[path]["status"] != "stale"):
            raise ValueError("source evidence mismatch")
    old_contents = read_blobs([old_tree[path]["blob"] for path in PATHS])
    current_contents = read_blobs([current_tree[path]["blob"] for path in PATHS])
    files, ranges = [], []
    for path, old, current in zip(PATHS, old_contents, current_contents):
        files.append({"path": path, "old_blob": old_tree[path]["blob"], "old_mode": old_tree[path]["mode"],
                      "current_blob": current_tree[path]["blob"], "current_mode": current_tree[path]["mode"]})
        matcher = difflib.SequenceMatcher(None, old.decode("utf-8").splitlines(),
                                          current.decode("utf-8").splitlines(), autojunk=False)
        for op, old_start, old_end, new_start, new_end in matcher.get_opcodes():
            if op == "equal":
                continue
            if op not in ("insert", "delete", "replace"):
                raise ValueError("unsupported alignment opcode")
            ranges.append({"path": path, "op": op, "old_start": old_start, "old_end": old_end,
                           "new_start": new_start, "new_end": new_end})
    return {"format": 1, "pin": PIN, "old_revision": old_revision, "current_revision": current_revision,
            "files": files, "ranges": ranges}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: stale-lifecycle-ranges.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    actual = strict_json(OUTPUT.read_text())
    if not same_json(actual, expected):
        raise SystemExit("lifecycle range receipt differs from pinned sources")
    count = 0
    for key, fields in (("files", ("remove", "duplicate", "old_blob", "current_blob", "old_mode")),
                        ("ranges", ("remove", "duplicate", "op", "old_start", "new_start"))):
        rows = actual[key]
        for index, row in enumerate(rows):
            for field in fields:
                if field == "remove":
                    changed = rows[:index] + rows[index + 1:]
                elif field == "duplicate":
                    changed = rows + [row]
                else:
                    changed = rows[:index] + [{**row, field: -1 if field.endswith("start") else "planted"}] + rows[index + 1:]
                if same_json(changed, expected[key]):
                    raise SystemExit("a planted error was accepted")
                count += 1
    print(f"checked {len(actual['files'])} sources and {len(actual['ranges'])} ranges; rejected {count} planted errors")


if __name__ == "__main__":
    main()

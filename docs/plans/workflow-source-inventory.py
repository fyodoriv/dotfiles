#!/usr/bin/env python3
"""Record lexical workflow run candidates from pinned Git blobs."""
import copy
import json
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from git_blob_batch import read_blobs

REVISION = "22ba4eede4a982187563e1b299aecfedb6246b41"
RECEIPT = Path("docs/plans/workflow-source-inventory.json")


def generate():
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION, "--", ".github/workflows"])
    tree = {}
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind != "blob":
            raise ValueError("unexpected workflow tree entry")
        tree[path.decode("utf-8")] = {"mode": mode, "blob": blob}
    if len(tree) != 5:
        raise ValueError("unexpected workflow scope")
    contents = read_blobs([item["blob"] for item in tree.values()])
    files = [{"path": path, **item} for path, item in tree.items()]
    candidates = []
    for (path, identity), content in zip(tree.items(), contents):
        lines = content.decode("utf-8").splitlines()
        for index, line in enumerate(lines):
            stripped = line.lstrip(" ")
            if not (stripped.startswith("run:") or stripped.startswith("- run:")):
                continue
            indent = len(line) - len(stripped)
            value = stripped.split("run:", 1)[1].strip()
            body = [line]
            if re.fullmatch(r"[|>][+-]?(?:\s+#.*)?", value):
                for continuation in lines[index + 1:]:
                    if continuation.strip() and len(continuation) - len(continuation.lstrip(" ")) <= indent:
                        break
                    body.append(continuation)
                if not any(item.strip() for item in body[1:]):
                    raise ValueError("empty or ambiguous block")
            candidates.append({"path": path, "blob": identity["blob"], "line": index + 1, "content": body})
    return {"format": 1, "revision": REVISION, "files": files, "candidates": candidates}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: workflow-source-inventory.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    receipt = json.loads(RECEIPT.read_text())
    if receipt != expected:
        raise SystemExit("workflow source receipt does not match pinned sources")
    count = 0
    for key, fields in (("files", ("remove", "duplicate", "blob", "mode")),
                        ("candidates", ("remove", "duplicate", "blob", "line", "content"))):
        for index in range(len(receipt[key])):
            for field in fields:
                case = copy.deepcopy(receipt)
                rows = case[key]
                if field == "remove":
                    rows.pop(index)
                elif field == "duplicate":
                    rows.append(copy.deepcopy(rows[index]))
                else:
                    rows[index][field] = -1 if field == "line" else ["planted"] if field == "content" else "planted"
                if case == expected:
                    raise SystemExit("a planted error was accepted")
                count += 1
    print(f"checked {len(receipt['files'])} workflows and {len(receipt['candidates'])} run candidates; rejected {count} planted errors")


if __name__ == "__main__":
    main()

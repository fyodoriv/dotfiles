#!/usr/bin/env python3
"""Record pinned CI script identities and bounded literal references."""
import copy
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json
from git_blob_batch import read_blobs

REVISION = "d70f8f0143857bff55eb3460b7a20a05bc1fd1cc"
RECEIPT = Path("docs/plans/ci-source-inventory.json")


def generate():
    raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION, "--",
                                   ".github/scripts", ".github/workflows", "Makefile"])
    tree = {}
    for entry in raw.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind != "blob":
            raise ValueError("unexpected tree entry")
        tree[path.decode("utf-8")] = {"mode": mode, "blob": blob}
    paths = list(tree)
    contents = read_blobs([tree[path]["blob"] for path in paths])
    lines = {path: content.decode("utf-8").splitlines() for path, content in zip(paths, contents)}
    scripts = [path for path in paths if path.startswith(".github/scripts/")]
    if len(scripts) != 5 or "Makefile" not in tree:
        raise ValueError("unexpected script scope")
    names = {path: Path(path).name for path in scripts}
    files = [{"path": path, **tree[path], "first_line": lines[path][0]} for path in scripts]
    references = []
    for path in paths:
        if path != "Makefile" and not path.startswith(".github/workflows/"):
            continue
        for number, text in enumerate(lines[path], 1):
            matched = [name for name in names.values() if name in text]
            if matched:
                references.append({"path": path, "blob": tree[path]["blob"], "line": number,
                                   "text": text, "names": matched})
    return {"format": 1, "revision": REVISION, "files": files, "references": references}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: ci-source-inventory.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    receipt = strict_json(RECEIPT.read_text())
    if not same_json(receipt, expected):
        raise SystemExit("CI source receipt does not match pinned sources")
    count = 0
    for key, fields in (("files", ("remove", "duplicate", "blob", "mode", "first_line")),
                        ("references", ("remove", "duplicate", "blob", "line", "text", "names"))):
        for index in range(len(receipt[key])):
            for field in fields:
                case = copy.deepcopy(receipt)
                rows = case[key]
                if field == "remove":
                    rows.pop(index)
                elif field == "duplicate":
                    rows.append(copy.deepcopy(rows[index]))
                else:
                    rows[index][field] = -1 if field == "line" else ["planted"] if field == "names" else "planted"
                if case == expected:
                    raise SystemExit("a planted error was accepted")
                count += 1
    print(f"checked {len(receipt['files'])} scripts and {len(receipt['references'])} references; rejected {count} planted errors")


if __name__ == "__main__":
    main()

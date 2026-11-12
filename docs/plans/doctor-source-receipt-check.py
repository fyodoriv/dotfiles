#!/usr/bin/env python3
"""Check the pinned doctor source receipt and reject planted errors."""
import copy
import json
import re
import subprocess
import sys
from pathlib import Path

if sys.argv[1:] == []:
    REVISION = "a846166aa1a14158cb6a5fef9a1c06ed3c0711f1"
    RECEIPT = Path("docs/plans/doctor-source-receipt.json")
    FAMILY, EXPECTED = "modules/", 33
elif sys.argv[1:] in (["--libraries"], ["--generate-libraries"]):
    REVISION = "57a4b14da82ad42c47bceebfc4e051d8bb9541d3"
    RECEIPT = Path("docs/plans/rust-library-source-receipt.json")
    FAMILY, EXPECTED = "lib/", 63
else:
    raise SystemExit("usage: doctor-source-receipt-check.py [--libraries|--generate-libraries]")
raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION, "--", FAMILY])
tree = {}
for record in raw.split(b"\0"):
    if not record:
        continue
    meta, path = record.split(b"\t", 1)
    path = path.decode("utf-8")
    if FAMILY == "modules/" and not re.fullmatch(r"modules/[^/]+/doctor\.sh", path):
        continue
    mode, kind, blob = meta.decode("ascii").split()
    if kind != "blob" or path in tree:
        raise SystemExit("invalid source tree")
    tree[path] = {"mode": mode, "blob": blob}
if len(tree) != EXPECTED:
    raise SystemExit("unexpected source family size")
lines = {
    path: subprocess.check_output(["git", "show", f"{REVISION}:{path}"]).decode("utf-8").splitlines()
    for path in tree
}


if sys.argv[1:] == ["--generate-libraries"]:
    generated = {
        "format": 1,
        "revision": REVISION,
        "files": [{"path": path, **identity} for path, identity in tree.items()],
        "anchors": [
            {"path": path, "line": 1, "text": source[0]}
            for path, source in lines.items()
        ],
    }
    print(json.dumps(generated, indent=2))
    raise SystemExit(0)


def valid(data):
    try:
        if type(data) is not dict or set(data) != {"format", "revision", "files", "anchors"}:
            return False
        if type(data["format"]) is not int or data["format"] != 1 or data["revision"] != REVISION:
            return False
        files, anchors = data["files"], data["anchors"]
        if type(files) is not list or type(anchors) is not list:
            return False
        found = {}
        for row in files:
            if type(row) is not dict or set(row) != {"path", "mode", "blob"}:
                return False
            path = row["path"]
            if type(path) is not str or path in found:
                return False
            found[path] = {"mode": row["mode"], "blob": row["blob"]}
        if found != tree:
            return False
        seen = set()
        for row in anchors:
            if type(row) is not dict or set(row) != {"path", "line", "text"}:
                return False
            path, number, text = row["path"], row["line"], row["text"]
            if type(path) is not str or path not in lines or type(number) is not int:
                return False
            if not 1 <= number <= len(lines[path]) or type(text) is not str:
                return False
            if lines[path][number - 1] != text or (path, number) in seen:
                return False
            seen.add((path, number))
        if FAMILY == "lib/":
            return len(anchors) == len(tree) and seen == {(path, 1) for path in tree}
        return {path for path, _ in seen} == set(tree)
    except (KeyError, TypeError, ValueError):
        return False


data = json.loads(RECEIPT.read_text(encoding="utf-8"))
if not valid(data):
    raise SystemExit("receipt does not match pinned sources")
mutants = []
for index, row in enumerate(data["files"]):
    for field in ("remove", "blob", "mode", "duplicate", "anchors"):
        case = copy.deepcopy(data)
        if field == "remove":
            case["files"].pop(index)
        elif field == "duplicate":
            case["files"].append(copy.deepcopy(case["files"][index]))
        elif field == "anchors":
            case["anchors"] = [anchor for anchor in case["anchors"] if anchor["path"] != row["path"]]
        else:
            case["files"][index][field] = "invalid"
        mutants.append(case)
for index in range(len(data["anchors"])):
    for field in ("line", "text", "duplicate"):
        case = copy.deepcopy(data)
        if field == "duplicate":
            case["anchors"].append(copy.deepcopy(case["anchors"][index]))
        else:
            case["anchors"][index][field] = -1 if field == "line" else "invalid planted text"
        mutants.append(case)
if FAMILY == "lib/":
    path = next(path for path, source in lines.items() if len(source) > 1)
    case = copy.deepcopy(data)
    case["anchors"].append({"path": path, "line": 2, "text": lines[path][1]})
    mutants.append(case)
if not mutants or any(valid(case) for case in mutants):
    raise SystemExit("a planted error was accepted")
print(f"checked {len(tree)}/{EXPECTED} files and {len(data['anchors'])} anchors; rejected {len(mutants)} planted errors")

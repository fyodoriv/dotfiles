#!/usr/bin/env python3
"""Check the pinned doctor source receipt and reject planted errors."""
import copy
import json
import re
import subprocess
from pathlib import Path

REVISION = "a846166aa1a14158cb6a5fef9a1c06ed3c0711f1"
RECEIPT = Path("docs/plans/doctor-source-receipt.json")
raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", REVISION, "--", "modules/"])
tree = {}
for record in raw.split(b"\0"):
    if not record:
        continue
    meta, path = record.split(b"\t", 1)
    path = path.decode("utf-8")
    if not re.fullmatch(r"modules/[^/]+/doctor\.sh", path):
        continue
    mode, kind, blob = meta.decode("ascii").split()
    if kind != "blob" or path in tree:
        raise SystemExit("invalid source tree")
    tree[path] = {"mode": mode, "blob": blob}
if len(tree) != 33:
    raise SystemExit("unexpected source family size")
lines = {
    path: subprocess.check_output(["git", "show", f"{REVISION}:{path}"]).decode("utf-8").splitlines()
    for path in tree
}


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
if not mutants or any(valid(case) for case in mutants):
    raise SystemExit("a planted error was accepted")
print(f"checked {len(tree)}/33 files and {len(data['anchors'])} anchors; rejected {len(mutants)} planted errors")

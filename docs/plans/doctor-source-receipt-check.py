#!/usr/bin/env python3
"""Check the pinned doctor source receipt and reject planted errors."""
import copy
import json
import re
import subprocess
import sys
from pathlib import Path

def library_caller_receipt():
    revision = "57a4b14da82ad42c47bceebfc4e051d8bb9541d3"
    tree_raw = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision])
    tree = {}
    for entry in tree_raw.split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        path = raw_path.decode("utf-8")
        if kind == "blob":
            tree[path] = blob
    names = sorted({Path(path).name for path in tree if path.startswith("lib/")})
    if len(names) != 63:
        raise SystemExit("unexpected library names")
    command = ["git", "grep", "-n", "-z", "-I", "-F"]
    for name in names:
        command.extend(["-e", name])
    command.extend([revision, "--", ":(exclude)docs/plans/rust-source-inventory-evidence.json"])
    result = subprocess.run(command, stdout=subprocess.PIPE, check=False)
    if result.returncode not in (0, 1):
        raise SystemExit("source search failed")
    remaining = result.stdout
    rows = []
    while remaining:
        raw_path, remaining = remaining.split(b"\0", 1)
        raw_line, remaining = remaining.split(b"\0", 1)
        raw_text, remaining = remaining.split(b"\n", 1)
        prefix = (revision + ":").encode()
        if not raw_path.startswith(prefix):
            raise SystemExit("unexpected search revision")
        path = raw_path[len(prefix):].decode("utf-8")
        text = raw_text.decode("utf-8")
        if re.match(r"^\s*(?:source|\.)\s+", text):
            rows.append({"path": path, "blob": tree[path], "line": int(raw_line),
                         "text": text, "names": [name for name in names if name in text]})
    if len(rows) != 277 or len({row["path"] for row in rows}) != 123:
        raise SystemExit("unexpected source-syntax scope")
    return {"format": 1, "revision": revision, "rows": rows}


if sys.argv[1:] in (["--library-callers"], ["--generate-library-callers"]):
    expected = library_caller_receipt()
    if sys.argv[1:] == ["--generate-library-callers"]:
        print(json.dumps(expected, indent=2))
        raise SystemExit(0)
    receipt = json.loads(Path("docs/plans/rust-library-caller-receipt.json").read_text(encoding="utf-8"))
    expected_bytes = json.dumps(expected, sort_keys=True)

    def matches(candidate):
        return json.dumps(candidate, sort_keys=True) == expected_bytes

    if not matches(receipt):
        raise SystemExit("caller receipt does not match pinned sources")
    count = 0
    for index in range(len(receipt["rows"])):
        for field in ("remove", "duplicate", "blob", "line", "text", "names"):
            case = copy.deepcopy(receipt)
            if field == "remove":
                case["rows"].pop(index)
            elif field == "duplicate":
                case["rows"].append(copy.deepcopy(case["rows"][index]))
            elif field == "line":
                case["rows"][index][field] = -1
            elif field == "names":
                case["rows"][index][field] = ["invalid"]
            else:
                case["rows"][index][field] = "invalid"
            if matches(case):
                raise SystemExit("a planted caller error was accepted")
            count += 1
    print(f"checked {len(receipt['rows'])} source-syntax rows; rejected {count} planted errors")
    raise SystemExit(0)


if sys.argv[1:] == []:
    REVISION = "a846166aa1a14158cb6a5fef9a1c06ed3c0711f1"
    RECEIPT = Path("docs/plans/doctor-source-receipt.json")
    FAMILY, EXPECTED = "modules/", 33
elif sys.argv[1:] in (["--libraries"], ["--generate-libraries"]):
    REVISION = "57a4b14da82ad42c47bceebfc4e051d8bb9541d3"
    RECEIPT = Path("docs/plans/rust-library-source-receipt.json")
    FAMILY, EXPECTED = "lib/", 63
elif sys.argv[1:] in (["--git-hooks"], ["--generate-git-hooks"]):
    REVISION = "81bcb6879d481d2ba3dedde256db278255b6e1ee"
    RECEIPT = Path("docs/plans/rust-git-hook-source-receipt.json")
    FAMILY, EXPECTED = "git-hooks/", 3
else:
    raise SystemExit("usage: doctor-source-receipt-check.py [--libraries|--generate-libraries|--library-callers|--generate-library-callers|--git-hooks|--generate-git-hooks]")
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


git_hook_anchors = {
    "git-hooks/commit-msg": [1, 95, 100],
    "git-hooks/pre-commit": [1, 38, 49, 55, 93, 304],
    "git-hooks/pre-push": [1, 38, 53, 124, 159, 286, 299, 333, 336, 353],
}
if sys.argv[1:] in (["--generate-libraries"], ["--generate-git-hooks"]):
    selected = {path: [1] for path in tree} if FAMILY == "lib/" else git_hook_anchors
    generated = {
        "format": 1,
        "revision": REVISION,
        "files": [{"path": path, **identity} for path, identity in tree.items()],
        "anchors": [
            {"path": path, "line": number, "text": lines[path][number - 1]}
            for path in tree for number in selected[path]
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
        if FAMILY == "git-hooks/":
            return seen == {(path, number) for path, numbers in git_hook_anchors.items() for number in numbers}
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
    fields = ("line", "text", "duplicate", "remove") if FAMILY == "git-hooks/" else ("line", "text", "duplicate")
    for field in fields:
        case = copy.deepcopy(data)
        if field == "remove":
            case["anchors"].pop(index)
        elif field == "duplicate":
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

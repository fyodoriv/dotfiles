#!/usr/bin/env python3
"""Join pinned source identity receipts without assigning ownership."""
import json
from pathlib import Path
import re
import subprocess
import sys

PIN = "e80b74812d2c697ad82886ff891d2a0884fc117b"
OUTPUT = Path("docs/plans/source-evidence-join.json")
INDEX = "docs/plans/tracked-source-candidates.json"
CHECKER = "docs/plans/tracked-source-candidates.py"
RECEIPTS = (
    "docs/plans/rust-current-bin-source-receipt.json",
    "docs/plans/rust-library-source-receipt.json",
    "docs/plans/doctor-source-receipt.json",
    "docs/plans/rust-scripts-source-receipt.json",
    "docs/plans/rust-root-source-receipt.json",
    "docs/plans/rust-git-hook-source-receipt.json",
    "docs/plans/agent-hook-source-receipt.json",
    "docs/plans/ci-source-inventory.json",
    "docs/plans/rust-source-inventory-evidence.json",
    "docs/plans/tooling-checkup-callers.json",
    "docs/plans/current-doctor-anchors.json",
)


def git(*args):
    return subprocess.check_output(["git", *args])


def strict_json(data):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON field")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=unique)


def tree(revision):
    result = {}
    for entry in git("ls-tree", "-r", "-z", revision).split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        path = raw_path.decode("utf-8")
        if kind == "blob":
            if path in result:
                raise ValueError("duplicate tree path")
            result[path] = {"mode": mode, "blob": blob}
    return result


def join(candidates, evidence):
    paths = [row["path"] for row in candidates]
    keys = [(row["receipt"], row["path"]) for row in evidence]
    if len(paths) != len(set(paths)) or len(keys) != len(set(keys)):
        raise ValueError("duplicate identity")
    by_path = {}
    for item in evidence:
        by_path.setdefault(item["path"], []).append(item)
    rows = []
    for candidate in candidates:
        links = []
        for item in by_path.get(candidate["path"], []):
            blob_match = item["blob"] == candidate["blob"]
            mode_match = item["mode"] == candidate["mode"]
            links.append({"receipt": item["receipt"], "revision": item["revision"],
                          "source_blob": item["blob"], "source_mode": item["mode"],
                          "blob_match": blob_match, "mode_match": mode_match,
                          "status": "exact" if blob_match and mode_match else "stale"})
        status = "exact" if any(link["status"] == "exact" for link in links) else "stale" if links else "absent"
        rows.append({**candidate, "status": status, "evidence": links})
    return rows


def extract_records(name, data, source_tree):
    ledger = name.endswith("rust-source-inventory-evidence.json")
    ci = name.endswith("ci-source-inventory.json")
    references = ci or name.endswith("tooling-checkup-callers.json")
    expected_keys = ({"format", "revision", "files", "generated_outputs", "outside_scope_references", "relationships"} if ledger else
                     {"format", "revision", "files", "references"} if references else {"format", "revision", "files", "anchors"})
    expected_format = "dotfiles-source-collection-v1" if ledger else 1
    if (type(data) is not dict or set(data) != expected_keys or type(data["format"]) is not type(expected_format) or
            data["format"] != expected_format):
        raise ValueError("unsupported receipt schema")
    revision = data["revision"]
    if type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("invalid source revision")
    if ledger:
        if type(data["files"]) is not dict:
            raise ValueError("invalid ledger files")
        try:
            records = [{"path": row["source_path"], "blob": row["git_blob"]} for row in data["files"].values()]
        except (KeyError, TypeError):
            raise ValueError("invalid ledger identity") from None
    else:
        if type(data["files"]) is not list:
            raise ValueError("invalid receipt files")
        records = data["files"]
    if not records:
        raise ValueError("empty receipt")
    seen, evidence = set(), []
    for row in records:
        if type(row) is not dict or not {"path", "blob"}.issubset(row):
            raise ValueError("invalid source identity")
        if not ledger and set(row) != ({"path", "mode", "blob", "first_line"} if ci else {"path", "mode", "blob"}):
            raise ValueError("unsupported identity schema")
        path, blob = row["path"], row["blob"]
        if type(path) is not str or path in seen or path not in source_tree or source_tree[path]["blob"] != blob:
            raise ValueError("source identity mismatch")
        mode = source_tree[path]["mode"]
        if not ledger and row.get("mode") != mode:
            raise ValueError("source mode mismatch")
        seen.add(path)
        evidence.append({"receipt": name, "revision": revision, "path": path, "mode": mode, "blob": blob})
    return evidence


def prior_links_preserved(old, new):
    if type(old) is not list or type(new) is not list or len(old) != len(new):
        return False
    for before, after in zip(old, new):
        if any(before.get(key) != after.get(key) for key in ("path", "mode", "blob", "reasons")):
            return False
        if any(link not in after.get("evidence", []) for link in before.get("evidence", [])):
            return False
    return True


def generate():
    pin_tree = tree(PIN)
    pinned_index = git("show", f"{PIN}:{INDEX}")
    pinned_checker = git("show", f"{PIN}:{CHECKER}")
    if Path(INDEX).read_bytes() != pinned_index or Path(CHECKER).read_bytes() != pinned_checker:
        raise ValueError("candidate checker differs from pinned input")
    subprocess.run([sys.executable, CHECKER, "--check"], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=True)
    index = strict_json(pinned_index)
    if type(index) is not dict or set(index) != {"format", "revision", "files"} or type(index["format"]) is not int or index["format"] != 1:
        raise ValueError("invalid candidate index")
    source_trees = {}
    inputs, evidence = [], []
    for name in RECEIPTS:
        if name not in pin_tree:
            raise ValueError("missing pinned receipt")
        data = strict_json(git("show", f"{PIN}:{name}"))
        if type(data) is not dict:
            raise ValueError("unsupported receipt schema")
        revision = data.get("revision")
        if type(revision) is not str or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("invalid source revision")
        if revision not in source_trees:
            source_trees[revision] = tree(revision)
        evidence.extend(extract_records(name, data, source_trees[revision]))
        inputs.append({"path": name, "blob": pin_tree[name]["blob"], "revision": revision})
    candidates = index["files"]
    if type(candidates) is not list:
        raise ValueError("invalid candidates")
    rows = join(candidates, evidence)
    old = strict_json(git("show", "3d3b904ea144b3b49fac3130d3f28c9ddcd205c1:docs/plans/source-evidence-join.json"))
    if not prior_links_preserved(old["candidates"], rows):
        raise ValueError("prior source evidence was lost")
    return {"format": 1, "pin": PIN, "index_blob": pin_tree[INDEX]["blob"],
            "candidate_revision": index["revision"], "inputs": inputs, "candidates": rows}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: source-evidence-join.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print('{\n  "format": 1,')
        for key in ("pin", "index_blob", "candidate_revision", "inputs"):
            print(f'  {json.dumps(key)}: {json.dumps(expected[key])},')
        print('  "candidates": [')
        for index, row in enumerate(expected["candidates"]):
            suffix = "," if index + 1 < len(expected["candidates"]) else ""
            print(f"    {json.dumps(row)}{suffix}")
        print('  ]\n}')
        return
    actual = strict_json(OUTPUT.read_text())
    if actual != expected:
        raise SystemExit("source evidence join differs from pinned inputs")
    rows, count = actual["candidates"], 0
    for index, row in enumerate(rows):
        changes = (rows[:index] + rows[index + 1:], rows + [row],
                   *(rows[:index] + [{**row, field: "planted"}] + rows[index + 1:]
                     for field in ("path", "blob", "mode", "status", "evidence")))
        for changed in changes:
            if changed == expected["candidates"]:
                raise SystemExit("a planted error was accepted")
            count += 1
    for index, item in enumerate(actual["inputs"]):
        for changed in (actual["inputs"][:index] + actual["inputs"][index + 1:],
                        *([*actual["inputs"][:index], {**item, field: "planted"}, *actual["inputs"][index + 1:]]
                          for field in ("blob", "revision"))):
            if changed == expected["inputs"]:
                raise SystemExit("a planted input error was accepted")
            count += 1
    print(f"checked {len(rows)} candidates; rejected {count} planted errors")


if __name__ == "__main__":
    main()

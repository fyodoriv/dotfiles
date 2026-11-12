#!/usr/bin/env python3
"""Record exact literal references to unresolved test-tree candidates."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "025f0a0473f9f60d27d07d8a1ef47fcc1ec1787b"
OUTPUT = Path("docs/plans/test-source-references.json")


def generate():
    source = strict_json(subprocess.check_output(["git", "show", f"{PIN}:docs/plans/bats-discovery-receipt.json"]))
    revision = source["candidate_revision"]
    candidates = [row for row in source["records"] if row["discovery"] == "unresolved"]
    paths = [row["path"] for row in candidates]
    if len(paths) != 40 or len(set(paths)) != 40:
        raise ValueError("unexpected candidate set")
    tree = {}
    raw_tree = subprocess.check_output(["git", "ls-tree", "-r", "-z", revision, "--", "tests/"])
    for entry in raw_tree.split(b"\0"):
        if not entry:
            continue
        meta, path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        if kind != "blob":
            raise ValueError("non-blob test source")
        tree[path.decode("utf-8")] = (mode, blob)
    if any(tree.get(row["path"]) != (row["mode"], row["blob"]) for row in candidates):
        raise ValueError("candidate identity mismatch")
    args = ["git", "grep", "--no-color", "-I", "-z", "-n", "-F"]
    for path in paths:
        args.extend(("-e", path))
    args.extend((revision, "--", "."))
    process = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if process.returncode not in (0, 1):
        raise ValueError("pinned reference search failed")
    found = {path: set() for path in paths}
    prefix = (revision + ":").encode("ascii")
    remaining = process.stdout
    while remaining:
        location, remaining = remaining.split(b"\0", 1)
        number, remaining = remaining.split(b"\0", 1)
        content, separator, remaining = remaining.partition(b"\n")
        if not separator:
            raise ValueError("unterminated reference line")
        if not location.startswith(prefix) or not number.isdigit() or int(number) <= 0:
            raise ValueError("invalid reference location")
        file = location[len(prefix):].decode("utf-8")
        for path in paths:
            if path.encode("utf-8") in content:
                found[path].add((file, int(number)))
    records = [{"path": row["path"], "mode": row["mode"], "blob": row["blob"],
                "references": [{"file": file, "line": line} for file, line in sorted(found[row["path"]])]}
               for row in candidates]
    return {"format": 1, "pin": PIN, "candidate_revision": revision,
            "candidate_count": len(records), "referenced_count": sum(bool(row["references"]) for row in records),
            "reference_count": sum(len(row["references"]) for row in records),
            "location_count": len({(ref["file"], ref["line"]) for row in records for ref in row["references"]}),
            "records": records}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: test-source-references.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("reference receipt differs from pinned source")
    print(f"checked {result['candidate_count']} candidates and {result['reference_count']} exact references")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check three explicit fixture test targets at the pinned source revision."""
import json
from pathlib import Path
import subprocess
import sys
import tomllib

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "025f0a0473f9f60d27d07d8a1ef47fcc1ec1787b"
ROOT = "tests/fixtures/compiler-queue-observer"
OUTPUT = Path("docs/plans/compiler-fixture-targets.json")
TARGETS = {"epoch.rs": "compiler_queue_epoch", "harness.rs": "compiler_queue_harness",
           "receipts.rs": "compiler_queue_receipts"}


def declarations(manifest):
    try:
        package = manifest["package"]
        tests = manifest["test"]
        if (package.get("edition") != "2021" or any(package.get(key) is not False
                for key in ("autolib", "autobins", "autotests")) or type(tests) is not list or len(tests) != 3):
            return False
        return {row["path"]: row["name"] for row in tests} == TARGETS and len({row["path"] for row in tests}) == 3
    except (KeyError, TypeError):
        return False


def generate():
    source = strict_json(subprocess.check_output(["git", "show", f"{PIN}:docs/plans/bats-discovery-receipt.json"]))
    revision = source["candidate_revision"]
    candidates = {row["path"]: row for row in source["records"] if row["discovery"] == "unresolved"}
    tree = {}
    for item in subprocess.check_output(["git", "ls-tree", "-r", "-z", revision, "--", ROOT]).split(b"\0"):
        if item:
            meta, path = item.split(b"\t", 1)
            mode, kind, blob = meta.decode("ascii").split()
            if kind != "blob": raise ValueError("non-blob fixture source")
            tree[path.decode("utf-8")] = (mode, blob)
    manifest_path = f"{ROOT}/Cargo.toml"
    manifest = tomllib.loads(subprocess.check_output(["git", "show", f"{revision}:{manifest_path}"]).decode("utf-8"))
    if not declarations(manifest): raise ValueError("fixture declarations changed")
    records = []
    for name, target in TARGETS.items():
        path = f"{ROOT}/{name}"
        row = candidates[path]
        if tree.get(path) != (row["mode"], row["blob"]): raise ValueError("candidate identity mismatch")
        records.append({"path": path, "mode": row["mode"], "blob": row["blob"], "target": target})
    return {"format": 1, "pin": PIN, "candidate_revision": revision,
            "manifest": {"path": manifest_path, "mode": tree[manifest_path][0], "blob": tree[manifest_path][1]},
            "records": records}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: compiler-fixture-targets.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("compiler fixture target receipt differs from pinned source")
    print("checked 3 explicit compiler fixture test declarations")


if __name__ == "__main__":
    main()

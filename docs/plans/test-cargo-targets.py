#!/usr/bin/env python3
"""Check bounded Cargo fixture target declarations at the source pin."""
import json
from pathlib import Path
import subprocess
import sys
import tomllib

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "025f0a0473f9f60d27d07d8a1ef47fcc1ec1787b"
OUTPUT = Path("docs/plans/test-cargo-targets.json")
ROOTS = ("tests/fixtures/checkup-read-consumer", "tests/fixtures/connector-credentials")
FILES = (f"{ROOTS[0]}/src/main.rs", f"{ROOTS[0]}/tests/read_guard.rs",
         f"{ROOTS[1]}/src/connector_credentials.rs", f"{ROOTS[1]}/tests/connector_credentials_contracts.rs")


def git(*args):
    return subprocess.check_output(["git", *args])


def generate():
    source = strict_json(git("show", f"{PIN}:docs/plans/bats-discovery-receipt.json"))
    revision = source["candidate_revision"]
    entries = {row["path"]: row for row in source["records"] if row["discovery"] == "unresolved"}
    tree = {}
    for item in git("ls-tree", "-r", "-z", revision, "--", *ROOTS).split(b"\0"):
        if item:
            meta, path = item.split(b"\t", 1)
            mode, kind, blob = meta.decode("ascii").split()
            if kind != "blob": raise ValueError("non-blob fixture source")
            tree[path.decode("utf-8")] = (mode, blob)
    if any(path not in entries or tree.get(path) != (entries[path]["mode"], entries[path]["blob"]) for path in FILES):
        raise ValueError("candidate identity mismatch")
    manifest_paths = [f"{root}/Cargo.toml" for root in ROOTS]
    raw = [git("show", f"{revision}:{path}") for path in manifest_paths]
    consumer, connector = [tomllib.loads(data.decode("utf-8")) for data in raw]
    cp, xp = consumer["package"], connector["package"]
    if (cp.get("edition") != "2021" or cp.get("autobins", True) is not True or
            cp.get("autotests", True) is not True or "bin" in consumer or "test" in consumer or
            xp.get("edition") != "2021" or any(xp.get(key) is not False for key in ("autolib", "autobins", "autotests")) or
            type(connector.get("test")) is not list or len(connector["test"]) != 1 or
            connector["test"][0].get("path") != "tests/connector_credentials_contracts.rs"):
        raise ValueError("fixture target declarations changed")
    test_lines = git("show", f"{revision}:{FILES[3]}").decode("utf-8").splitlines()
    if test_lines[1:3] != ['#[path = "../src/connector_credentials.rs"]', "mod connector_credentials;"]:
        raise ValueError("fixture module declaration changed")
    kinds = ("default_binary", "default_integration_test", "test_module", "explicit_integration_test")
    records = [{"path": path, "mode": entries[path]["mode"], "blob": entries[path]["blob"], "kind": kind}
               for path, kind in zip(FILES, kinds)]
    manifests = [{"path": path, "mode": tree[path][0], "blob": tree[path][1]} for path in manifest_paths]
    return {"format": 1, "pin": PIN, "candidate_revision": revision, "manifests": manifests,
            "module_anchor": {"file": FILES[3], "lines": [2, 3]}, "records": records}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: test-cargo-targets.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("fixture target receipt differs from pinned sources")
    print("checked 4 fixture sources: 3 targets and 1 test module")


if __name__ == "__main__":
    main()

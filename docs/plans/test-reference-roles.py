#!/usr/bin/env python3
"""Record selected explicit declarations among pinned test references."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "b93b8a6a7b50613cc971ae1a5069e7e17dbb084d"
OUTPUT = Path("docs/plans/test-reference-roles.json")
CLAIMS = {
    "tests/e2e/hermetic-exec.sh": ("tests/e2e/stories-e2e.bats", 26, "invocation", 'in_home() { "$REPO/tests/e2e/hermetic-exec.sh" "$SCRATCH" "$@"; }'),
    "tests/e2e/hermetic-install.sh": ("tests/e2e/stories-e2e.bats", 20, "invocation", '  "$REPO/tests/e2e/hermetic-install.sh" "$SCRATCH" run --yes --profile core \\'),
    "tests/e2e/needs-e2e.sh": ("Makefile", 201, "invocation", '\t@if paths=$$(./tests/e2e/needs-e2e.sh); then \\'),
    "tests/git_blob_batch_test.py": ("tests/git-blob-batch.bats", 4, "invocation", '  run python3 tests/git_blob_batch_test.py'),
    "tests/hook_rss_provenance_test.py": ("tests/hook-rss-provenance.bats", 4, "invocation", '  run python3 tests/hook_rss_provenance_test.py'),
    "tests/hook_trusted_launch_test.py": ("tests/hook-trusted-launch.bats", 4, "invocation", '  run python3 tests/hook_trusted_launch_test.py'),
    "tests/verify-counts-doc-paths.sh": ("bin/bats-affected", 25, "source", 'source "$DOTFILES_DIR/tests/verify-counts-doc-paths.sh"'),
}


def generate():
    source = strict_json(subprocess.check_output(["git", "show", f"{PIN}:docs/plans/test-source-references.json"]))
    revision = source["candidate_revision"]
    rows = [row for row in source["records"] if row["references"]]
    if len(rows) != 24 or not set(CLAIMS).issubset({row["path"] for row in rows}):
        raise ValueError("unexpected reference set")
    records = []
    for row in rows:
        path = row["path"]
        if path not in CLAIMS:
            records.append({"path": path, "role": "unresolved", "anchor": None})
            continue
        file, line, role, expected = CLAIMS[path]
        if {"file": file, "line": line} not in row["references"]:
            raise ValueError("anchor is not a retained reference")
        text = subprocess.check_output(["git", "show", f"{revision}:{file}"]).decode("utf-8").splitlines()
        if line > len(text) or text[line - 1] != expected:
            raise ValueError("declaration changed")
        records.append({"path": path, "role": role, "anchor": {"file": file, "line": line}})
    return {"format": 1, "pin": PIN, "candidate_revision": revision, "records": records,
            "declared_count": sum(row["role"] != "unresolved" for row in records)}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: test-reference-roles.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("reference role receipt differs from pinned source")
    print(f"checked {len(result['records'])} candidates and {result['declared_count']} declarations")


if __name__ == "__main__":
    main()

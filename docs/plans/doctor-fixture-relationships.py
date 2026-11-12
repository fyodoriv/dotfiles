#!/usr/bin/env python3
"""Bind two conditional fixture routes to pinned source, without running them."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

REVISION = "94eef660b9d531b401f1f78c7c788101eb3e7bfb"
RECEIPT = Path("docs/plans/doctor-fixture-relationships.json")
CANDIDATES = {
    "tests/fixtures/json-fail-fix-module/doctor.sh": ("100755", "8e566f0272dfb9abfe5faf1c534aa922d214fefb"),
    "tests/fixtures/notification-fail-module/doctor.sh": ("100755", "69d7deaec83fec81b8a7de6091264cc78e64ac4e"),
}
ANCHORS = {
    "tests/doctor-json-status.bats": {
        18: 'REPO_ROOT="$BATS_TEST_DIRNAME/.."',
        23: '  export DOTFILES_DOCTOR_FIXTURE_DIR="$REPO_ROOT/tests/fixtures"',
        50: '  out="$("$REPO_ROOT/bin/dotfiles-doctor" --module json-fail-fix-module --json --fix 2>/dev/null || true)"',
    },
    "tests/doctor-notification.bats": {
        15: 'REPO_ROOT="$BATS_TEST_DIRNAME/.."',
        33: '  export DOTFILES_DOCTOR_FIXTURE_DIR="$REPO_ROOT/tests/fixtures"',
        55: '  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module',
    },
    "bin/dotfiles-doctor": {
        106: 'MODULE_DIRS=("$DOTFILES_DIR/modules")',
        109: 'if [ -n "${DOTFILES_DOCTOR_FIXTURE_DIR:-}" ] && [ -n "${BATS_TEST_FILENAME:-}" ] && [ -d "$DOTFILES_DOCTOR_FIXTURE_DIR" ]; then',
        110: '  MODULE_DIRS+=("$DOTFILES_DOCTOR_FIXTURE_DIR")',
        265: '    --module)',
        267: '      MODULE_FILTER="$2"',
        271: '      for parent in "${MODULE_DIRS[@]}"; do',
        272: '        if [ -d "$parent/$MODULE_FILTER" ]; then',
        273: '          MODULE_FILTER_PATH="$parent/$MODULE_FILTER"',
        274: '          break',
        795: 'run_module_doctor() {',
        797: '  run_module_doctor_inner "$@"',
        801: 'run_module_doctor_inner() {',
        802: '  local module_dir="$1"',
        805: '  local doctor_file="$module_dir/doctor.sh"',
        806: '  [ ! -f "$doctor_file" ] && return',
        890: '    source "$doctor_file"',
        894: '    source "$doctor_file"',
        906: 'if [ -n "$MODULE_FILTER" ]; then',
        909: '  if [ -n "$PLUGIN_FILTER_NAME" ]; then',
        914: '  else',
        915: '    run_module_doctor "$MODULE_FILTER_PATH"',
    },
}


def validate(identities, sources):
    if identities != CANDIDATES:
        raise ValueError("fixture identity mismatch")
    for path, anchors in ANCHORS.items():
        lines = sources[path].splitlines()
        for line, expected in anchors.items():
            if line > len(lines) or lines[line - 1] != expected:
                raise ValueError("source anchor mismatch")
    return {
        "revision": REVISION,
        "candidates": [{"path": path, "mode": mode, "blob": blob} for path, (mode, blob) in CANDIDATES.items()],
        "anchors": {path: list(anchors) for path, anchors in ANCHORS.items()},
        "relationship": "conditional fixture-root module selection and source",
        "limits": "Bats marker and fixture directory required; earlier matching core module wins; no execution or caller coverage inferred",
    }


def snapshot():
    identities = {}
    for path in CANDIDATES:
        entry = subprocess.check_output(["git", "ls-tree", REVISION, "--", path], text=True).strip()
        metadata, actual_path = entry.split("\t", 1)
        mode, kind, blob = metadata.split()
        if kind != "blob" or actual_path != path:
            raise ValueError("unexpected fixture tree entry")
        identities[path] = (mode, blob)
    sources = {path: subprocess.check_output(["git", "show", f"{REVISION}:{path}"], text=True) for path in ANCHORS}
    return identities, sources


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: doctor-fixture-relationships.py --generate|--check")
    result = validate(*snapshot())
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
    elif not same_json(strict_json(RECEIPT.read_text()), result):
        raise SystemExit("fixture relationship receipt differs from pinned source")
    else:
        print("checked 2 conditional fixture relationships")


if __name__ == "__main__":
    main()

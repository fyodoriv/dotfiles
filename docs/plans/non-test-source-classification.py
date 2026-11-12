#!/usr/bin/env python3
"""Verify a bounded, content-free review against pinned source identities."""
import json
from pathlib import Path
import subprocess
import sys

sys.dont_write_bytecode = True
from git_blob_batch import read_blobs
from strict_receipt_json import same_json, strict_json

PIN = "9e12006246eab25962be0a94311bc4d2a1f3e9fb"
OUTPUT = Path("docs/plans/non-test-source-classification.json")
# Populated from source review. Spans are one-based, inclusive.
REVIEW = {
    '.chezmoi.yaml.tmpl': ('unresolved', 38, 38),
    'data/plugin-template/doctor/example/doctor.sh': ('executable-source', 3, 3),
    'data/plugin-template/tests/plugin.bats': ('executable-source', 4, 4),
    'data/plugin-template/validate/example.sh': ('executable-source', 2, 2),
    'docs/plans/ci-source-inventory.py': ('executable-source', 3, 3),
    'docs/plans/current-bin-boundaries.py': ('executable-source', 3, 3),
    'docs/plans/doctor-source-receipt-check.py': ('executable-source', 3, 3),
    'docs/plans/git_blob_batch.py': ('executable-source', 6, 6),
    'docs/plans/workflow-source-inventory.py': ('executable-source', 3, 3),
    'dot_config/agentbrew/hooks-overlay/modify_manifest.yaml.tmpl': ('executable-source', 1, 1),
    'dot_config/dotfiles/bash-env.sh.tmpl': ('executable-source', 4, 4),
    'dot_config/dotfiles/env.sh.tmpl': ('executable-source', 3, 3),
    'dot_config/topgrade.toml.tmpl': ('unresolved', 116, 116),
    'dot_gitconfig.personal.tmpl': ('generated-input', 6, 6),
    'dot_gitconfig.tmpl': ('unresolved', 108, 108),
    'home/git-editor': ('executable-source', 1, 1),
    'home/sleep': ('executable-source', 1, 1),
    'home/wakeup': ('executable-source', 1, 1),
    'launchagents/com.dotfiles.agent-scratch-prune.plist.tmpl': ('generated-input', 13, 13),
    'launchagents/com.dotfiles.telemetry.plist.tmpl': ('generated-input', 21, 21),
    'private_dot_agent-browser/executable_ensure-chrome.sh': ('executable-source', 1, 1),
    'private_dot_agent-browser/executable_launch-chrome.sh': ('executable-source', 1, 1),
    'private_dot_agent-browser/modify_config.json': ('executable-source', 1, 1),
    'private_dot_ssh/private_config.tmpl': ('generated-input', 1, 1),
    'symlink_dot_git-editor.tmpl': ('generated-input', 1, 1),
    'symlink_dot_gitcommit_template.tmpl': ('generated-input', 1, 1),
    'symlink_dot_gitignore_global.tmpl': ('generated-input', 1, 1),
    'symlink_dot_ideavimrc.tmpl': ('generated-input', 1, 1),
    'symlink_dot_sleep.tmpl': ('generated-input', 1, 1),
    'symlink_dot_tmux.conf.tmpl': ('generated-input', 1, 1),
    'symlink_dot_wakeup.tmpl': ('generated-input', 1, 1),
    'symlink_dot_zshenv.tmpl': ('generated-input', 1, 1),
    'symlink_dot_zshrc.ai-tools.tmpl': ('generated-input', 1, 1),
    'symlink_dot_zshrc.tmpl': ('generated-input', 1, 1),
}


def git(*args):
    return subprocess.check_output(["git", *args])


def generate():
    joined = strict_json(git("show", f"{PIN}:docs/plans/source-evidence-join.json"))
    rows = [row for row in joined["candidates"]
            if row["status"] == "absent" and not row["path"].startswith("tests/")]
    if len(rows) != 34 or len({row["path"] for row in rows}) != 34:
        raise ValueError("unexpected or duplicate candidate set")
    if set(REVIEW) != {row["path"] for row in rows}:
        raise ValueError("review does not cover the candidate set")
    revision = joined["candidate_revision"]
    tree = {}
    for entry in git("ls-tree", "-r", "-z", revision, "--", *(r["path"] for r in rows)).split(b"\0"):
        if not entry:
            continue
        meta, raw_path = entry.split(b"\t", 1)
        mode, kind, blob = meta.decode("ascii").split()
        path = raw_path.decode("utf-8")
        if kind != "blob" or path in tree:
            raise ValueError("invalid source identity")
        tree[path] = (mode, blob)
    if set(tree) != set(REVIEW):
        raise ValueError("candidate source missing")
    contents = read_blobs([row["blob"] for row in rows])
    records = []
    for row, content in zip(rows, contents):
        path, mode, blob = row["path"], row["mode"], row["blob"]
        category, start, end = REVIEW[path]
        if tree[path] != (mode, blob):
            raise ValueError("candidate identity mismatch")
        if category not in ("executable-source", "generated-input", "unresolved"):
            raise ValueError("invalid review category")
        if not (type(start) is int and type(end) is int and 1 <= start <= end <= len(content.splitlines())):
            raise ValueError("invalid source span")
        records.append({"path": path, "mode": mode, "blob": blob,
                        "category": category, "start_line": start, "end_line": end})
    return {"format": 1, "pin": PIN, "candidate_revision": revision, "records": records}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: non-test-source-classification.py --generate|--check")
    expected = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(expected, indent=2))
        return
    actual = strict_json(OUTPUT.read_text())
    if not same_json(actual, expected):
        raise SystemExit("classification receipt differs from pinned review")
    count = 0
    for index, row in enumerate(expected["records"]):
        for field in ("remove", "duplicate", "path", "mode", "blob", "category", "start_line", "end_line"):
            if field == "remove":
                changed = expected["records"][:index] + expected["records"][index + 1:]
            elif field == "duplicate":
                changed = expected["records"] + [row]
            else:
                planted = -1 if field.endswith("_line") else "planted"
                changed = expected["records"][:index] + [{**row, field: planted}] + expected["records"][index + 1:]
            if same_json(changed, expected["records"]):
                raise SystemExit("a planted error was accepted")
            count += 1
    print(f"checked {len(actual['records'])} sources; rejected {count} planted errors")


if __name__ == "__main__":
    main()

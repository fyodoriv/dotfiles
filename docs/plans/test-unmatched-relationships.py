#!/usr/bin/env python3
"""Check bounded source declarations for previously unmatched test files."""
import json
from pathlib import Path
import subprocess
import sys
import tomllib

sys.dont_write_bytecode = True
from strict_receipt_json import same_json, strict_json

PIN = "b93b8a6a7b50613cc971ae1a5069e7e17dbb084d"
OUTPUT = Path("docs/plans/test-unmatched-relationships.json")
CLAIMS = {
    "tests/fixtures/fake-cdp-dom-ws.mjs": ("invocation", [("tests/agent-tab.bats", 405, '  node "$BATS_TEST_DIRNAME/fixtures/fake-cdp-dom-ws.mjs" "$TEST_DIR/port" "$TEST_DIR/dom.log" &')]),
    "tests/fixtures/fake-cdp-eval-ws.mjs": ("invocation", [("tests/agent-tab.bats", 326, '  "$REAL_NODE" "$BATS_TEST_DIRNAME/fixtures/fake-cdp-eval-ws.mjs" "$TEST_DIR/port" ${1:-} &')]),
    "tests/fixtures/fake-cdp-ws.mjs": ("invocation", [("tests/agent-tab.bats", 297, '  node "$BATS_TEST_DIRNAME/fixtures/fake-cdp-ws.mjs" "$TEST_DIR/port" 300000 &')]),
    "tests/fixtures/fake-slack-page.mjs": ("indirect_invocation", [("tests/slack-draft.bats", 7, 'PAGE="$BATS_TEST_DIRNAME/fixtures/fake-slack-page.mjs"'), ("tests/slack-draft.bats", 25, '        out="$(node "$PAGE" "$5")"; echo "$out"')]),
    "tests/fixtures/gate-attribution/controls.py": ("invocation", [("tests/gate-attribution.bats", 4, '  run python3 "$BATS_TEST_DIRNAME/fixtures/gate-attribution/controls.py" valid_success')]),
    "tests/fixtures/gate-attribution/join.py": ("adjacent_import", [("tests/fixtures/gate-attribution/controls.py", 7, 'from join import join')]),
    "tests/fixtures/heavy-run-discovery-json-model.py": ("indirect_invocation", [("tests/heavy-run-discovery-json.bats", 4, '  export MODEL="$BATS_TEST_DIRNAME/fixtures/heavy-run-discovery-json-model.py"'), ("tests/heavy-run-discovery-json.bats", 34, '    "$MODEL_PYTHON" -I -S "$MODEL"')]),
    "tests/fixtures/queue-privacy-cutover/activation.rs": ("cargo_test", [("tests/fixtures/queue-privacy-cutover/Cargo.toml", 13, 'path = "activation.rs"')]),
    "tests/helpers/doctor-status-diagnostic.bash": ("source", [("tests/doctor-json-status.bats", 19, 'source "$BATS_TEST_DIRNAME/helpers/doctor-status-diagnostic.bash"')]),
    "tests/helpers/realtime-probe.bash": ("bats_load", [("tests/heavy-run.bats", 6, 'load helpers/realtime-probe')]),
    "tests/verify-counts-exemptions.sh": ("source", [("tests/verify-counts.bats", 8, 'source "$BATS_TEST_DIRNAME/verify-counts-exemptions.sh"')]),
}


def git(*args):
    return subprocess.check_output(["git", *args])


def generate():
    refs = strict_json(git("show", f"{PIN}:docs/plans/test-source-references.json"))
    cargo = strict_json(git("show", f"{PIN}:docs/plans/test-cargo-targets.json"))
    revision = refs["candidate_revision"]
    done = {row["path"] for row in cargo["records"]}
    rows = [row for row in refs["records"] if not row["references"] and row["path"] not in done]
    if len(rows) != 12 or not set(CLAIMS).issubset({row["path"] for row in rows}):
        raise ValueError("unexpected unmatched source set")
    tree = {}
    for item in git("ls-tree", "-r", "-z", revision, "--", "tests/").split(b"\0"):
        if item:
            meta, path = item.split(b"\t", 1)
            mode, kind, blob = meta.decode("ascii").split()
            if kind != "blob": raise ValueError("non-blob test source")
            tree[path.decode("utf-8")] = (mode, blob)
    if any(tree.get(row["path"]) != (row["mode"], row["blob"]) for row in rows):
        raise ValueError("candidate identity changed")
    manifest_path = "tests/fixtures/queue-privacy-cutover/Cargo.toml"
    manifest = tomllib.loads(git("show", f"{revision}:{manifest_path}").decode("utf-8"))
    if (manifest["package"].get("autotests") is not False or type(manifest.get("test")) is not list or
            len(manifest["test"]) != 1 or manifest["test"][0].get("path") != "activation.rs"):
        raise ValueError("fixture target changed")
    records = []
    source_lines = {}
    for row in rows:
        path = row["path"]
        if path not in CLAIMS:
            records.append({"path": path, "mode": row["mode"], "blob": row["blob"], "role": "unresolved", "anchors": []})
            continue
        role, anchors = CLAIMS[path]
        for file, number, expected in anchors:
            if file not in source_lines:
                source_lines[file] = git("show", f"{revision}:{file}").decode("utf-8").splitlines()
            lines = source_lines[file]
            if number > len(lines) or lines[number - 1] != expected: raise ValueError("source declaration changed")
        records.append({"path": path, "mode": row["mode"], "blob": row["blob"], "role": role,
                        "anchors": [{"file": file, "line": number} for file, number, _ in anchors]})
    return {"format": 1, "pin": PIN, "candidate_revision": revision,
            "records": records, "declared_count": sum(row["role"] != "unresolved" for row in records)}


def main():
    if sys.argv[1:] not in (["--generate"], ["--check"]):
        raise SystemExit("usage: test-unmatched-relationships.py --generate|--check")
    result = generate()
    if sys.argv[1:] == ["--generate"]:
        print(json.dumps(result, indent=2))
        return
    if not same_json(strict_json(OUTPUT.read_text()), result):
        raise SystemExit("unmatched source receipt differs from pinned source")
    print(f"checked {len(result['records'])} candidates and {result['declared_count']} declarations")


if __name__ == "__main__":
    main()

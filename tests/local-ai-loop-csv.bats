#!/usr/bin/env bats
# Pin lib/local-ai-loop.py's per-task run ledger: one row per processed
# task appended to docs/audits/local-ai-loop-runs.csv (loop-owned — the
# agent's 14-column telemetry keeps local-ai-runs.csv). Second slice of
# the overnight-grind epic — see docs/plans/overnight-grind-summary-csv.md.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
HEADER="timestamp_utc,task_id,source,outcome,wall_seconds,turn_budget"

_record() {
  # _record <repo> <task-json> <outcome> <wall> <turns>
  python3 - "$REPO_ROOT" "$@" <<'PY'
import importlib.util, json, sys, os
root = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
repo, task, outcome, wall, turns = (
    sys.argv[2], json.loads(sys.argv[3]), sys.argv[4],
    float(sys.argv[5]), int(sys.argv[6]),
)
m.record_run_row(repo, task, outcome, wall, turns)
print("recorded: ok")
PY
}

setup() {
  TMP=$(mktemp -d)
  CSV="$TMP/docs/audits/local-ai-loop-runs.csv"
}

teardown() { rm -rf "$TMP"; }

@test "csv: first row creates the file with header + one row" {
  run _record "$TMP" '{"id": "t-one"}' completed 12.6 14
  [ "$status" -eq 0 ]
  [ -f "$CSV" ]
  [ "$(head -1 "$CSV")" = "$HEADER" ]
  [ "$(wc -l < "$CSV" | tr -d ' ')" = "2" ]
  grep -q "t-one,tasks-md,completed,13,14" "$CSV"
}

@test "csv: second append adds a row without duplicating the header" {
  _record "$TMP" '{"id": "t-one"}' completed 10 14
  _record "$TMP" '{"id": "t-two"}' check-failed 3 18
  [ "$(grep -c "$HEADER" "$CSV")" = "1" ]
  [ "$(wc -l < "$CSV" | tr -d ' ')" = "3" ]
  grep -q "t-two,tasks-md,check-failed,3,18" "$CSV"
}

@test "csv: queue source derived from _queue_file; outcome verbatim" {
  run _record "$TMP" '{"id": "t-q", "_queue_file": "/tmp/q/spec.md"}' reviewer-failed 7 14
  [ "$status" -eq 0 ]
  grep -q "t-q,queue,reviewer-failed,7,14" "$CSV"
}

@test "csv: write failure warns but does not raise" {
  mkdir -p "$TMP/docs/audits"
  chmod 555 "$TMP/docs/audits"
  run _record "$TMP" '{"id": "t-ro"}' completed 5 14
  chmod 755 "$TMP/docs/audits"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recorded: ok"* ]]
  [[ "$output" == *"⚠"* ]]
}

@test "csv: dry-run records nothing" {
  QUEUE="$TMP/q"
  mkdir -p "$QUEUE"
  printf '%s\n' "- [ ] Dry task" "  - **ID**: t-dry" > "$QUEUE/spec.md"
  run python3 "$REPO_ROOT/lib/local-ai-loop.py" \
    --dry-run --queue "$QUEUE" --cwd "$TMP" --max-tasks 1
  [ "$status" -eq 0 ]
  [ ! -f "$CSV" ]
}

@test "csv: stubbed-agent integration — completed and agent-failed rows" {
  # Fixture repo: stub agent that creates the declared file, no-op make
  # check, git identity isolated from host hooks/excludes.
  FIX="$TMP/fixture"
  mkdir -p "$FIX/bin" "$FIX/tests" "$FIX/q"
  ( cd "$FIX" && git -c init.defaultBranch=main init -q && \
      git config core.hooksPath /dev/null && \
      git config core.excludesFile /dev/null && \
      git config user.email "t@x.com" && git config user.name "t" && \
      git commit --allow-empty -q -m "init" )
  printf '%s\n' "check:" "	@true" > "$FIX/Makefile"
  cat > "$FIX/bin/local-ai-agent" <<'STUB'
#!/bin/bash
# stub agent: succeed and produce the declared deliverable
echo '@test "x" { [ 1 -eq 1 ]; }' > tests/t-int.bats
exit "${STUB_AGENT_RC:-0}"
STUB
  chmod +x "$FIX/bin/local-ai-agent"
  printf '%s\n' "- [ ] Integration task" "  - **ID**: t-int" \
    "  - **Files**: tests/t-int.bats" > "$FIX/q/spec.md"

  run python3 "$REPO_ROOT/lib/local-ai-loop.py" \
    --queue "$FIX/q" --cwd "$FIX" --max-tasks 1
  [ "$status" -eq 0 ]
  grep -q "t-int,queue,completed," "$FIX/docs/audits/local-ai-loop-runs.csv"

  # Failure pass: fresh spec, stub exits 1 → agent-failed row.
  printf '%s\n' "- [ ] Failing task" "  - **ID**: t-fail" \
    "  - **Files**: tests/t-fail.bats" > "$FIX/q/spec2.md"
  STUB_AGENT_RC=1 run python3 "$REPO_ROOT/lib/local-ai-loop.py" \
    --queue "$FIX/q" --cwd "$FIX" --max-tasks 1
  grep -q "t-fail,queue,agent-failed," "$FIX/docs/audits/local-ai-loop-runs.csv"
}

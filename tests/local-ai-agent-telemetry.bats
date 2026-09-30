#!/usr/bin/env bats
# Pin the telemetry that bin/local-ai-agent writes to
# docs/audits/local-ai-runs.csv. Each agent run emits one row so we
# can grep trends (success rate, median tok/s, blocked-done count)
# without a Python detour.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
MOCK_PY="$BATS_TEST_DIRNAME/fixtures/mock-ollama.py"

setup() {
  TMPDIR_RUN=$(mktemp -d)
  PORT=$((20000 + RANDOM % 500))
  # Telemetry expects docs/audits/ inside cwd.
  mkdir -p "$TMPDIR_RUN/docs/audits"
}

_start_mock() {
  local script_json="$1"
  python3 "$MOCK_PY" "$PORT" "$script_json" \
    >"$TMPDIR_RUN/mock.log" 2>&1 &
  MOCK_PID=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z 127.0.0.1 "$PORT" 2>/dev/null; then break; fi
    sleep 0.2
  done
}

teardown() {
  if [ -n "${MOCK_PID:-}" ] && ps -p "$MOCK_PID" >/dev/null 2>&1; then
    command kill "$MOCK_PID" 2>/dev/null || true
    wait "$MOCK_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR_RUN"
}

@test "telemetry: --telemetry off → no CSV written" {
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "ok", "tool_calls": []}, "eval_count": 10, "eval_duration": 100000000}
]
JSON
  _start_mock "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 2 --cwd "$TMPDIR_RUN" "noop"
  [ "$status" -eq 0 ]
  [ ! -f "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" ]
}

@test "telemetry: --telemetry on → CSV row appended with header" {
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "ok", "tool_calls": []}, "eval_count": 10, "eval_duration": 100000000}
]
JSON
  _start_mock "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 2 --cwd "$TMPDIR_RUN" --telemetry "noop"
  [ "$status" -eq 0 ]
  [ -f "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" ]
  # Header
  head -1 "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -q "ts,model,outcome,turns,elapsed_s,writes,bashes,verifies"
  # One data row
  [ "$(wc -l < "$TMPDIR_RUN/docs/audits/local-ai-runs.csv")" -eq 2 ]
  # outcome column (3rd) should be "stopped" (no tool calls = stop)
  awk -F, 'NR==2 {print $3}' "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -q "stopped"
}

@test "telemetry: outcome=done when agent successfully calls done" {
  cat > "$TMPDIR_RUN/Makefile" <<'MK'
check:
	@true
MK
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "x.txt", "content": "hi"}}}]}, "eval_count": 10, "eval_duration": 100000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "bash", "arguments": {"command": "make check"}}}]}, "eval_count": 10, "eval_duration": 100000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "ok"}}}]}, "eval_count": 10, "eval_duration": 100000000}
]
JSON
  _start_mock "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" --telemetry "task"
  [ "$status" -eq 0 ]
  awk -F, 'NR==2 {print $3}' "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -q "done"
  # writes=1, bashes=1, verifies=1 (columns 6/7/8)
  awk -F, 'NR==2 {print $6"_"$7"_"$8}' "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -q "1_1_1"
}

@test "telemetry: blocked_done counter increments when done is rejected" {
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "x.txt", "content": "hi"}}}]}, "eval_count": 10, "eval_duration": 100000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "ok"}}}]}, "eval_count": 10, "eval_duration": 100000000},
  {"message": {"content": "stopping", "tool_calls": []}, "eval_count": 10, "eval_duration": 100000000}
]
JSON
  _start_mock "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" --telemetry "task"
  [ "$status" -eq 0 ]
  # blocked_done column (9th) should be >= 1
  awk -F, 'NR==2 {print $9}' "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -qE '^[1-9]'
  # outcome should be "stopped" (agent gave up after the block)
  awk -F, 'NR==2 {print $3}' "$TMPDIR_RUN/docs/audits/local-ai-runs.csv" \
    | grep -q "stopped"
}

@test "telemetry: wrapper passes --telemetry by default" {
  # Sanity: the bin/local-ai-agent wrapper should inject --telemetry
  # unless LOCAL_AI_TELEMETRY=0. We grep the wrapper source.
  grep -q "LOCAL_AI_TELEMETRY" "$REPO_ROOT/bin/local-ai-agent"
  grep -q -- "--telemetry" "$REPO_ROOT/bin/local-ai-agent"
}

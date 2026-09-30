#!/usr/bin/env bats
# Pin the `done`-precondition added to lib/local-ai-agent.py: the
# agent must run `make check` or `bats tests/...` after its last
# write and that command must exit 0 before `done` is allowed.
# Failure mode: docs/audits/local-ai-failure-modes.md "`done` is gated
# on `make check`, not on the agent's word".
#
# Uses tests/fixtures/mock-ollama.py with a custom response script so
# we can simulate the agent making specific tool-call sequences without
# burning real model time.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
MOCK_PY="$BATS_TEST_DIRNAME/fixtures/mock-ollama.py"

setup() {
  TMPDIR_RUN=$(mktemp -d)
  PORT=$((19500 + RANDOM % 500))
}

_start_mock_with_script() {
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

@test "done is blocked when write happens but verification gate is never run" {
  # Script: write_file → done → (loop terminates with no tool calls)
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "scratch.txt", "content": "hi"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "wrote file"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "blocked, stopping", "tool_calls": []}, "eval_count": 5, "eval_duration": 1000000}
]
JSON
  _start_mock_with_script "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" "test task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done blocked"* ]]
  [[ "$output" == *"haven't run a passing"* && "$output" == *"make check"* ]]
}

@test "done is allowed when make check exits 0 after the last write" {
  cat > "$TMPDIR_RUN/Makefile" <<'MK'
check:
	@echo "fake check passed"
MK
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "scratch.txt", "content": "hi"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "bash", "arguments": {"command": "make check"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "verified"}}}]}, "eval_count": 5, "eval_duration": 1000000}
]
JSON
  _start_mock_with_script "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" "test task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== done ==="* ]]
  [[ "$output" != *"done blocked"* ]]
}

@test "done is blocked when make check FAILS after the last write" {
  # No Makefile → `make check` exits non-zero → gate stays red.
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "scratch.txt", "content": "hi"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "bash", "arguments": {"command": "make check"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "verified"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "stopping", "tool_calls": []}, "eval_count": 5, "eval_duration": 1000000}
]
JSON
  _start_mock_with_script "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" "test task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done blocked"* ]]
}

@test "done is blocked when only a narrow bats run (not make check) has passed" {
  # Tightening shipped after run-3 dogfood: the agent ran
  # `bats tests/<file>.bats` (only its own test) after make check failed,
  # then called done — got past the precondition because the gate
  # accepted any bats-tests invocation. New rule: ONLY `make check`
  # counts as a satisfied verification gate.
  cat > "$TMPDIR_RUN/script.json" <<JSON
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "x.txt", "content": "hi"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "bash", "arguments": {"command": "bats tests/some.bats"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "narrow bats passed"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "stopping", "tool_calls": []}, "eval_count": 5, "eval_duration": 1000000}
]
JSON
  _start_mock_with_script "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" "test task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done blocked"* ]]
  [[ "$output" == *"ONLY \`make check\`"* ]]
}

@test "done is blocked when bats test was written but critique_test was never called" {
  cat > "$TMPDIR_RUN/Makefile" <<'MK'
check:
	@true
MK
  cat > "$TMPDIR_RUN/script.json" <<'JSON'
[
  {"message": {"content": "", "tool_calls": [{"function": {"name": "write_file", "arguments": {"path": "tests/new.bats", "content": "@test x { [ 1 -eq 1 ]; }"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "bash", "arguments": {"command": "make check"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "", "tool_calls": [{"function": {"name": "done", "arguments": {"summary": "wrote test"}}}]}, "eval_count": 5, "eval_duration": 1000000},
  {"message": {"content": "stopping", "tool_calls": []}, "eval_count": 5, "eval_duration": 1000000}
]
JSON
  _start_mock_with_script "$TMPDIR_RUN/script.json"
  run env OLLAMA_HOST="http://127.0.0.1:$PORT" \
    python3 "$REPO_ROOT/lib/local-ai-agent.py" \
      --max-turns 5 --cwd "$TMPDIR_RUN" "task"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done blocked"* ]]
  [[ "$output" == *"haven't critiqued"* || "$output" == *"critique_test"* ]]
}

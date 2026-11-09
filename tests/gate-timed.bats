#!/usr/bin/env bats
# scripts/gate-timed.sh: per-step `make check` timings for the speed review.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
GT="$REPO_ROOT/scripts/gate-timed.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_GATE_TIMINGS_FILE="$TEST_DIR/gate-timings.jsonl"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "gate-timed logs the step, its seconds, and its status" {
  run "$GT" lint true
  [ "$status" -eq 0 ]
  jq -e '.step == "lint" and .status == 0 and (.seconds | type == "number") and (.ts | test("^20"))' "$DOTFILES_GATE_TIMINGS_FILE"
}

@test "gate-timed passes the step's failure through and logs it" {
  run "$GT" test bash -c 'exit 3'
  [ "$status" -eq 3 ]
  jq -e '.step == "test" and .status == 3' "$DOTFILES_GATE_TIMINGS_FILE"
}

@test "DOTFILES_GATE_TIMINGS=0 still runs the step but logs nothing" {
  run env DOTFILES_GATE_TIMINGS=0 "$GT" lint touch "$TEST_DIR/ran"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/ran" ]
  [ ! -e "$DOTFILES_GATE_TIMINGS_FILE" ]
}

@test "gate-timed refuses an unknown step name" {
  run "$GT" deploy true
  [ "$status" -eq 2 ]
}

@test "gate-timed binds every step to an invocation and prints a final receipt" {
  export DOTFILES_GATE_INVOCATION="2ba7ad64-9a70-4f5f-9152-9b0c2dd9ee11"
  run "$GT" lint true
  [ "$status" -eq 0 ]
  jq -e '.invocation == env.DOTFILES_GATE_INVOCATION' "$DOTFILES_GATE_TIMINGS_FILE"
  run "$GT" total bash -c 'exit 7'
  [ "$status" -eq 7 ]
  [[ "$output" == "gate-receipt: $DOTFILES_GATE_INVOCATION status=7" ]]
  jq -e 'select(.step == "total") | .invocation == env.DOTFILES_GATE_INVOCATION and .status == 7' "$DOTFILES_GATE_TIMINGS_FILE"
}

@test "gate-timed rejects an unsafe invocation label without running the command" {
  export DOTFILES_GATE_INVOCATION="private command text"
  run "$GT" total touch "$TEST_DIR/ran"
  [ "$status" -eq 2 ]
  [ ! -e "$TEST_DIR/ran" ]
  [[ "$output" != *"private command text"* ]]
}

@test "make check propagates one invocation to real step rows and its receipt" {
  local fixture="$TEST_DIR/repo"
  mkdir -p "$fixture/scripts"
  cp "$GT" "$fixture/scripts/gate-timed.sh"
  awk '/^check: ##/{copy=1} copy{print} copy && /Iterating\? Use/{exit}' \
    "$REPO_ROOT/Makefile" > "$fixture/Makefile"
  cat >> "$fixture/Makefile" <<'MAKE'
check-steps:
	@scripts/gate-timed.sh lint true
	@scripts/gate-timed.sh lint-tasks true
	@scripts/gate-timed.sh test true
	@scripts/gate-timed.sh plugins-bash32 true
	@scripts/gate-timed.sh e2e true
MAKE
  export DOTFILES_GATE_TIMINGS_FILE="$TEST_DIR/real-gate.jsonl"
  run env PATH="/usr/bin:/bin" make -C "$fixture" --no-print-directory check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  jq -s -e 'length == 6 and ([.[].invocation] | unique | length == 1) and .[-1].step == "total"' \
    "$DOTFILES_GATE_TIMINGS_FILE"
  local invocation
  invocation="$(jq -r 'select(.step == "total") | .invocation' "$DOTFILES_GATE_TIMINGS_FILE")"
  [[ "$output" == *"gate-receipt: $invocation status=0"* ]]
}

@test "make check times every gate step and the total" {
  for step in total lint lint-tasks test plugins-bash32 e2e; do
    grep -qE "gate-timed.sh $step " "$REPO_ROOT/Makefile" || { echo "untimed step: $step"; return 1; }
  done
  grep -q 'DOTFILES_GATE_INVOCATION=.*uuidgen' "$REPO_ROOT/Makefile"
}

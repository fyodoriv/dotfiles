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

@test "make check times every gate step and the total" {
  for step in total lint lint-tasks test e2e; do
    grep -qE "gate-timed.sh $step " "$REPO_ROOT/Makefile" || { echo "untimed step: $step"; return 1; }
  done
}

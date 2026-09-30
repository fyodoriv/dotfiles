#!/usr/bin/env bats
# Tests for the rule-9 / Hypothesis-Driven-Development field lint.
#
# Child task 1 of `per-module-rule9-hdd-audit` decomposition (blocking
# PR #104). The lint walks TASKS.md, finds P0/P1 entries, and exits
# nonzero for any missing the 5 fields.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
SCRIPT="$DOTFILES_DIR/.github/scripts/check-tasks-rule9-fields.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TASKS_RULE9_FILE="$TEST_DIR/TASKS.md"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "script is executable" {
  [ -x "$SCRIPT" ]
}

@test "exits 0 when TASKS.md is missing" {
  rm -f "$TASKS_RULE9_FILE"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
}

@test "compliant P1 task emits no warning" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Test task
  - **ID**: test-task
  - **Tags**: test
  - **Hypothesis**: Doing X causes Y measured by Z
  - **Success**: Metric >= 0.9
  - **Pivot**: Metric < 0.5 means approach is wrong
  - **Measurement**: bash -c "echo 0.95"
  - **Anchor**: Smith 2020 — Section 3
TASKS
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # Summary should say 1 task total, 0 non-compliant
  [[ "$output" == *"total=1 non_compliant=0"* ]]
  # No per-task warning should fire
  [[ "$output" != *"rule-9-fail: P1 test-task"* ]]
}

@test "P1 task missing all 5 fields fails with all 5 names" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Test task
  - **ID**: missing-everything
  - **Tags**: test
  - **Details**: just a description
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule-9-fail: P1 missing-everything missing: Hypothesis Success Pivot Measurement Anchor"* ]]
  [[ "$output" == *"total=1 non_compliant=1"* ]]
}

@test "P1 task missing only Pivot fails naming only Pivot" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Test task
  - **ID**: missing-pivot
  - **Tags**: test
  - **Hypothesis**: claim
  - **Success**: yes
  - **Measurement**: cmd
  - **Anchor**: cite
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule-9-fail: P1 missing-pivot missing: Pivot"* ]]
  [[ "$output" != *"missing: Hypothesis"* ]]
}

@test "P2 / P3 tasks are NOT enforced even when missing all 5 fields" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

## P2

- [ ] P2 task should not trigger warning
  - **ID**: p2-task
  - **Tags**: test

## P3

- [ ] P3 task should not trigger warning
  - **ID**: p3-task
  - **Tags**: test
TASKS
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # No warnings emitted at all (no P0/P1 entries)
  [[ "$output" != *"rule-9-fail:"* ]]
  [[ "$output" == *"total=0 non_compliant=0"* ]]
}

@test "claimed task (@agent-id) still requires rule-9 fields" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Claimed task (@devin-claude)
  - **ID**: claimed-task
  - **Tags**: test
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule-9-fail: P1 claimed-task"* ]]
}

@test "blocked task still requires rule-9 fields" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Blocked task
  - **ID**: blocked-task
  - **Tags**: test
  - **Blocked**: needs-decomposition
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rule-9-fail: P1 blocked-task"* ]]
}

@test "P0 + P1 mixed: counts and warnings are correct across sections" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

- [ ] Compliant P0
  - **ID**: ok-p0
  - **Tags**: test
  - **Hypothesis**: h
  - **Success**: s
  - **Pivot**: p
  - **Measurement**: m
  - **Anchor**: a

- [ ] Non-compliant P0
  - **ID**: bad-p0
  - **Tags**: test

## P1

- [ ] Non-compliant P1
  - **ID**: bad-p1
  - **Tags**: test
  - **Hypothesis**: only one field
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"total=3 non_compliant=2"* ]]
  [[ "$output" == *"rule-9-fail: P0 bad-p0"* ]]
  [[ "$output" == *"rule-9-fail: P1 bad-p1"* ]]
  [[ "$output" != *"rule-9-fail: P0 ok-p0"* ]]
}

@test "fails when any P0/P1 task is non-compliant" {
  cat > "$TASKS_RULE9_FILE" <<'TASKS'
# Tasks

## P0

- [ ] No fields P0
  - **ID**: no-fields-p0

## P1

- [ ] No fields P1
  - **ID**: no-fields-p1
TASKS
  run "$SCRIPT"
  [ "$status" -eq 1 ]
}

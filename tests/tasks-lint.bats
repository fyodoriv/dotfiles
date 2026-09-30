#!/usr/bin/env bats
# Tests for TASKS.md lint integration.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
MAKEFILE="$DOTFILES_DIR/Makefile"
CI_WORKFLOW="$DOTFILES_DIR/.github/workflows/ci.yml"
PRE_COMMIT="$DOTFILES_DIR/git-hooks/pre-commit"
VERSION_FILE="$DOTFILES_DIR/.tasks-lint-version"

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "make lint-tasks validates the queue" {
  run make -C "$DOTFILES_DIR" lint-tasks
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked 1 file(s), found 0 error(s)"* ]]
}

@test "make check includes TASKS.md linting" {
  grep -Eq '^check: .*lint-tasks' "$MAKEFILE"
}

@test "CI lint job runs TASKS.md linting" {
  grep -Fq 'make lint-tasks' "$CI_WORKFLOW"
}

@test "TASKS.md linter version is pinned in a repo-local constant" {
  grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$VERSION_FILE"
}

@test "Makefile uses the pinned TASKS.md linter package" {
  grep -Fq 'TASKS_LINT_VERSION := $(shell sed -n' "$MAKEFILE"
  grep -Fq '@tasks-md/lint@$(TASKS_LINT_VERSION)' "$MAKEFILE"
  ! grep -Fq 'npx -y @tasks-md/lint TASKS.md' "$MAKEFILE"
}

@test "pre-commit pins its TASKS.md lint and delegates project checks" {
  grep -Fq 'exec "$CURRENT_REPO/hooks/pre-commit" "$@"' "$PRE_COMMIT"
  grep -Fq '.tasks-lint-version' "$PRE_COMMIT"
  grep -Fq '"@tasks-md/lint${tasks_lint_version}"' "$PRE_COMMIT"
  ! grep -Fq 'npx -y @tasks-md/lint TASKS.md' "$PRE_COMMIT"
}

@test "malformed task queues fail deterministically" {
  cat > "$TEST_DIR/TASKS.md" <<'TASKS'
Tasks

## P0

- Missing checkbox syntax
TASKS

  version="$(sed -n '1p' "$VERSION_FILE")"
  run npx -y "@tasks-md/lint@$version" "$TEST_DIR/TASKS.md"
  [ "$status" -ne 0 ]
}

@test "make lint-tasks fails when a P1 task lacks rule-9 fields" {
  cat > "$TEST_DIR/TASKS.md" <<'TASKS'
# Tasks

## P0

## P1

- [ ] Missing rule-9 field
  - **ID**: missing-rule9
  - **Tags**: test
  - **Hypothesis**: h
  - **Success**: s
  - **Pivot**: p
  - **Anchor**: a

## P2

## P3
TASKS

  run make -C "$DOTFILES_DIR" lint-tasks TASKS_FILE="$TEST_DIR/TASKS.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"rule-9-fail: P1 missing-rule9 missing: Measurement"* ]]
}

# ── tasks-lint pin freshness audit ────────────────────────────────

FRESHNESS_SCRIPT="$DOTFILES_DIR/.github/scripts/check-tasks-lint-freshness.sh"

@test "freshness script exists and is executable" {
  [ -x "$FRESHNESS_SCRIPT" ]
}

@test "freshness script reports current pin as up to date" {
  pinned="$(sed -n '1p' "$VERSION_FILE")"
  run env TASKS_LINT_LATEST="$pinned" "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"is current"* ]]
  [[ "$output" != *"behind registry"* ]]
}

@test "freshness script flags a stale pin with remediation" {
  pinned="$(sed -n '1p' "$VERSION_FILE")"
  # Pick a version unambiguously ahead under `sort -V`. Prepending "999."
  # avoids depending on the actual semver components in the pin file.
  printf -v fake_latest '999.%s' "$pinned"

  run env TASKS_LINT_LATEST="$fake_latest" "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"behind registry latest $fake_latest"* ]]
  [[ "$output" == *"echo $fake_latest > .tasks-lint-version"* ]]
  [[ "$output" == *"make lint-tasks"* ]]
}

@test "freshness script accepts a pin that is ahead of the registry" {
  # Mirror lag and pre-release pins both produce this state. The audit
  # must stay non-fatal and clearly say the pin is at-or-ahead so the
  # operator doesn't see a false "behind" warning.
  pinned="$(sed -n '1p' "$VERSION_FILE")"
  run env TASKS_LINT_LATEST="0.0.1" TASKS_LINT_VERSION_FILE="$VERSION_FILE" "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"at or ahead"* ]]
}

@test "freshness script skips cleanly when latest lookup is unavailable" {
  run env TASKS_LINT_LATEST_FAIL=1 "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [[ "$output" == *"unavailable"* ]]
}

@test "freshness script skips cleanly when the pin file is missing" {
  run env TASKS_LINT_VERSION_FILE="$TEST_DIR/missing" "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [[ "$output" == *"not found"* ]]
}

@test "freshness script rejects a malformed pin without crashing" {
  printf 'not-a-version\n' > "$TEST_DIR/version"
  run env TASKS_LINT_VERSION_FILE="$TEST_DIR/version" "$FRESHNESS_SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [[ "$output" == *"invalid pin"* ]]
}

@test "Makefile target lint-tasks-freshness runs the audit" {
  grep -Eq '^lint-tasks-freshness:.*##' "$MAKEFILE"
  grep -Fq '.github/scripts/check-tasks-lint-freshness.sh' "$MAKEFILE"
}

@test "CI lint job runs the freshness audit non-fatally" {
  grep -Fq 'make lint-tasks-freshness' "$CI_WORKFLOW"
  # `continue-on-error: true` keeps the audit advisory — the lint job
  # passes even when a fresher tasks-md/lint is available so contributors
  # don't lose CI on an upstream release we haven't reviewed yet.
  awk '
    /make lint-tasks-freshness/ { found = 1 }
    found && /continue-on-error: true/ { ok = 1; exit }
    END { exit !ok }
  ' "$CI_WORKFLOW"
}

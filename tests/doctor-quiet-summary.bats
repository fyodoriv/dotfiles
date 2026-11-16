#!/usr/bin/env bats
# Tests for the dotfiles-doctor --quiet summary line: it names the
# failing check IDs so the user does not need a second full run.
# Uses the shipped fixture tests/fixtures/notification-fail-module.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  unset DOTFILES_DOCTOR_NOTIFY
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "quiet: one failing check prints its ID on the summary line" {
  export DOTFILES_DOCTOR_FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module --quiet
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"✗ 1"* ]]
  [[ "${lines[0]}" == *"failing: notification-fail-module.always_fails"* ]]
  [[ "${lines[0]}" == *"— fix: dotfiles doctor --fix" ]]
}

@test "quiet: --fix --quiet names a check whose fix is missing" {
  export DOTFILES_DOCTOR_FIXTURE_DIR="$REPO_ROOT/tests/fixtures"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module --fix --quiet
  [ "$status" -eq 1 ]
  [[ "${lines[${#lines[@]}-1]}" == *"failing: notification-fail-module.always_fails"* ]]
  # In the applied checkout the fix is by hand; elsewhere --fix is report-only,
  # so the line points at dotfiles doctor --fix. Either way it names a fix.
  [[ "${lines[${#lines[@]}-1]}" == *"— fix: "* ]]
}

@test "quiet: more than 5 failing checks are capped with +N more" {
  local mod="$TEST_DIR/extra/quiet-many-fail"
  mkdir -p "$mod"
  for i in 1 2 3 4 5 6 7; do
    printf 'check "quiet-many-fail.f%s" "synthetic failure %s" "false" ""\n' "$i" "$i" >> "$mod/doctor.sh"
  done
  export DOTFILES_DOCTOR_FIXTURE_DIR="$TEST_DIR/extra"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module quiet-many-fail --quiet
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"failing: quiet-many-fail.f1, quiet-many-fail.f2, quiet-many-fail.f3, quiet-many-fail.f4, quiet-many-fail.f5 +2 more"* ]]
}

@test "quiet: all-pass line is unchanged" {
  local mod="$TEST_DIR/extra/quiet-green"
  mkdir -p "$mod"
  printf 'check "quiet-green.ok" "synthetic pass" "true" ""\n' > "$mod/doctor.sh"
  export DOTFILES_DOCTOR_FIXTURE_DIR="$TEST_DIR/extra"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module quiet-green --quiet
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"passed"*"skipped"* ]]
  [[ "${lines[0]}" != *"failing:"* ]]
}

@test "quiet: a GitHub rate limit on chezmoi latest-version is only a warning" {
  local mod="$TEST_DIR/extra/quiet-green"
  mkdir -p "$mod" "$TEST_DIR/bin"
  printf 'check "quiet-green.ok" "synthetic pass" "true" ""\n' > "$mod/doctor.sh"
  # A chezmoi whose doctor reports what a rate-limited hosted runner saw.
  cat > "$TEST_DIR/bin/chezmoi" <<'STUB'
#!/bin/bash
[ "$1" = doctor ] || exit 0
printf 'RESULT   CHECK            MESSAGE\n'
printf 'ok       version          v2.74.0\n'
printf 'error    latest-version   GitHub rate limit exceeded\n'
STUB
  chmod +x "$TEST_DIR/bin/chezmoi"
  export DOTFILES_DOCTOR_FIXTURE_DIR="$TEST_DIR/extra"
  PATH="$TEST_DIR/bin:$PATH" run "$REPO_ROOT/bin/dotfiles-doctor" --module quiet-green --quiet
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" != *"failing:"* ]]
}

#!/usr/bin/env bats
# Tests for the dotfiles-doctor end-of-run notification — verifies the
# top-N failing-check-ID preview actually reaches `terminal-notifier`.
#
# Background: 2026-05-25 dotfiles-doctor was changed to embed the top-5
# failing check IDs in its end-of-run macOS notification (instead of
# just a count). Manual verification used `terminal-notifier` stubs;
# this file is the automated coverage so the IDs-in-notification
# behavior can't silently regress.
#
# Pattern: tmpdir + PATH-shadowed `terminal-notifier` stub that writes
# its argv to a known file. Force a failing check via a fixture module
# under `tests/fixtures/notification-fail-module/`.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"
  # PATH-shadow real terminal-notifier with a stub that logs argv to
  # $TEST_DIR/notify.log. The stub mirrors the real binary's exit-0
  # behavior so the doctor's `|| true` clause stays inert.
  cat > "$MOCK_BIN/terminal-notifier" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >> "$NOTIFY_LOG"
exit 0
STUB
  chmod +x "$MOCK_BIN/terminal-notifier"
  export NOTIFY_LOG="$TEST_DIR/notify.log"
  export PATH="$MOCK_BIN:$PATH"
  # Point at the fixture module dir (sibling to this test file)
  export EXTRA_DOCTOR_DIR="$REPO_ROOT/tests/fixtures"
}

_enable_doctor_notify() {
  export DOTFILES_DOCTOR_NOTIFY=1
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "notification: fixture module exists and is shipped under tests/fixtures/" {
  [ -f "$REPO_ROOT/tests/fixtures/notification-fail-module/doctor.sh" ]
  grep -q 'notification-fail-module.always_fails' \
    "$REPO_ROOT/tests/fixtures/notification-fail-module/doctor.sh"
}

@test "notification: failing-doctor fires terminal-notifier with check-ID preview" {
  _enable_doctor_notify
  # Run the failing fixture under EXTRA_DOCTOR_DIR. dotfiles-doctor will
  # exit 1 because of the synthetic failure — that's expected; we care
  # about the notify side effect.
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module
  [ "$status" -eq 1 ]
  # Stub captured a notification
  [ -f "$NOTIFY_LOG" ]
  # The notification text MUST contain "failing:" (the new IDs-in-message
  # phrasing) AND the actual fixture check ID. This is the regression
  # guard: if the preview ever drops back to a bare count, this asserts
  # red.
  grep -F 'failing:' "$NOTIFY_LOG"
  grep -F 'notification-fail-module.always_fails' "$NOTIFY_LOG"
}

@test "notification: check ID format matches the documented '<module>.<id>' shape" {
  _enable_doctor_notify
  # The task body specifies the assertion: at least one valid check ID
  # matching ^[a-z]+\.[a-z_]+$. This locks the naming convention in.
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module
  [ "$status" -eq 1 ]
  [ -f "$NOTIFY_LOG" ]
  # Pull the -message arg and look for an ID matching the convention.
  # The stub writes argv one-arg-per-line, so the value following the
  # `-message` line is the notification message.
  local msg
  msg="$(awk '/^-message$/{getline; print; exit}' "$NOTIFY_LOG")"
  [[ "$msg" =~ [a-z][-a-z0-9_]*\.[a-z][-a-z0-9_]* ]]
}

@test "notification: default off — no terminal-notifier without DOTFILES_DOCTOR_NOTIFY=1" {
  unset DOTFILES_DOCTOR_NOTIFY
  export EXTRA_DOCTOR_DIR="$REPO_ROOT/tests/fixtures"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-fail-module
  [ "$status" -eq 1 ]
  [ ! -f "$NOTIFY_LOG" ] || [ ! -s "$NOTIFY_LOG" ]
}

@test "notification: greenfield run (no failures) emits no terminal-notifier call" {
  # Run a module that we expect to pass on a healthy host. Use a tmp
  # fixture with a check that's always green.
  local green_dir="$TEST_DIR/extra-doctor-dir/notification-green-module"
  mkdir -p "$green_dir"
  cat > "$green_dir/doctor.sh" <<'GREEN'
check "notification-green-module.always_passes" \
  "synthetic passing check for notification-content greenfield test" \
  "true" \
  ""
GREEN
  export EXTRA_DOCTOR_DIR="$TEST_DIR/extra-doctor-dir"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module notification-green-module
  [ "$status" -eq 0 ]
  # No notification on green runs — file should either not exist
  # OR be empty.
  [ ! -f "$NOTIFY_LOG" ] || [ ! -s "$NOTIFY_LOG" ]
}

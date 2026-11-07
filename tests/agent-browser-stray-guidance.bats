#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" DOTFILES_DIR="$TEST_DIR/dot files"
  export CALL_LOG="$TEST_DIR/calls" REAP_STATUS=1
  mkdir -p "$HOME" "$DOTFILES_DIR/bin" "$DOTFILES_DIR/lib"
  cp "$BATS_TEST_DIRNAME/../lib/spotlight-probe.sh" "$DOTFILES_DIR/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/focus-steal-audit.sh" "$DOTFILES_DIR/lib/"
  cat > "$DOTFILES_DIR/bin/agent-browser-reap-strays" <<'HELPER'
#!/bin/bash
printf '%s\n' "$*" >> "$CALL_LOG"
exit "$REAP_STATUS"
HELPER
  chmod +x "$DOTFILES_DIR/bin/agent-browser-reap-strays"
  : > "$CALL_LOG"
  LIST_MODE=false
  JSON_MODE=false
  FIX_MODE=false
  FAIL_TEXT=""
  CHECK_STATE=""
  check() {
    [ "$1" = agent-browser.no_stray_newtab_targets ] || return 0
    if eval "$3" >/dev/null 2>&1; then
      CHECK_STATE=pass
    else
      CHECK_STATE=fail
      FAIL_TEXT="${5:-$2}"
      if $FIX_MODE && [ -n "$4" ]; then eval "$4"; fi
    fi
  }
  skipped() { :; }
}

teardown() { rm -rf "$TEST_DIR"; }

run_check() {
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
}

assert_dry_calls() {
  [ -s "$CALL_LOG" ]
  ! grep -vE '^--dry-run --quiet( --keep-one)?$' "$CALL_LOG"
}

@test "failing_guidance" {
  expected_path=$(printf '%q' "$DOTFILES_DIR/bin/agent-browser-reap-strays")
  for mode in false true; do
    FIX_MODE="$mode"
    : > "$CALL_LOG"
    run_check
    [ "$CHECK_STATE" = fail ]
    assert_dry_calls
    if [[ "$FAIL_TEXT" != *"Agent:"* || "$FAIL_TEXT" != *"$expected_path --dry-run"* || "$FAIL_TEXT" != *"authorization"* ]]; then
      echo 'missing dry-run guidance' >&3
      return 1
    fi
  done
}

@test "keep_one_guidance" {
  export DOTFILES_CHROME_KEEP_BLANK_WINDOW=true
  run_check
  [ "$CHECK_STATE" = fail ]
  assert_dry_calls
  grep -qx -- '--dry-run --quiet --keep-one' "$CALL_LOG"
  expected_path=$(printf '%q' "$DOTFILES_DIR/bin/agent-browser-reap-strays")
  [[ "$FAIL_TEXT" == *"$expected_path --dry-run --keep-one"* ]]
}

@test "passing_unchanged" {
  export REAP_STATUS=0
  run_check
  [ "$CHECK_STATE" = pass ]
  assert_dry_calls
}

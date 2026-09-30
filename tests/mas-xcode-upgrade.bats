#!/usr/bin/env bats
# Tests for bin/dotfiles-mas-upgrade — the Xcode-tolerant Mac App Store
# upgrade that replaces topgrade's built-in `mas` step.
#
# The bug it fixes: `mas upgrade` (upgrade-all) fails the whole step when it
# can't write Xcode's root-owned _MASReceipt, failing every `dotfiles upgrade`
# whenever the App Store re-reports Xcode as outdated.

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-mas-upgrade"
TOPGRADE_CFG="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml"

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  # Record which ids `mas upgrade` was asked to upgrade.
  UPGRADE_LOG="$TEST_DIR/upgrade.log"
  export UPGRADE_LOG
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Build a mock `mas` whose `outdated` output is supplied via $MOCK_OUTDATED.
# `mas upgrade <id>` logs the id and fails only for id 999 (a forced failure).
_make_mas() {
  cat > "$STUB_BIN/mas" <<'STUB'
#!/bin/bash
case "$1" in
  outdated) printf '%s\n' "$MOCK_OUTDATED" ;;
  upgrade)  echo "$2" >> "$UPGRADE_LOG"; [ "$2" = "999" ] && exit 1; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/mas"
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "topgrade disables the built-in mas step and wires the wrapper" {
  # `mas` must be in the disable list AND the wrapper command present.
  grep -qE '^\s*"mas",' "$TOPGRADE_CFG"
  grep -q 'dotfiles-mas-upgrade' "$TOPGRADE_CFG"
}

@test "skips Xcode but upgrades other outdated apps (exit 0)" {
  _make_mas
  export MOCK_OUTDATED="497799835 Xcode (26.4 -> 26.5)
123456789 SomeApp (1.0 -> 1.1)"
  MAS_BIN="$STUB_BIN/mas" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping Xcode"* ]]
  # SomeApp upgraded, Xcode NOT passed to `mas upgrade`
  grep -q '123456789' "$UPGRADE_LOG"
  ! grep -q '497799835' "$UPGRADE_LOG"
}

@test "Xcode-only outdated → exit 0 (the core regression fix)" {
  _make_mas
  export MOCK_OUTDATED="497799835 Xcode (26.4 -> 26.5)"
  MAS_BIN="$STUB_BIN/mas" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping Xcode"* ]]
  [ ! -f "$UPGRADE_LOG" ] || ! grep -q '497799835' "$UPGRADE_LOG"
}

@test "ignores the Spotlight 'not indexed' warning line in mas outdated" {
  _make_mas
  export MOCK_OUTDATED="Warning: Found a likely App Store app that is not indexed in Spotlight
123456789 SomeApp (1.0 -> 1.1)"
  MAS_BIN="$STUB_BIN/mas" run "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '123456789' "$UPGRADE_LOG"
}

@test "nothing outdated → exit 0 with a clean message" {
  _make_mas
  export MOCK_OUTDATED=""
  MAS_BIN="$STUB_BIN/mas" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing outdated"* ]]
}

@test "a genuine non-Xcode upgrade failure still fails the step (exit 1)" {
  _make_mas
  export MOCK_OUTDATED="999 BrokenApp (1.0 -> 1.1)"
  MAS_BIN="$STUB_BIN/mas" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed to upgrade"* ]]
}

@test "mas not installed → exit 0 (graceful skip)" {
  MAS_BIN="$TEST_DIR/bin/nonexistent-mas" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed"* ]]
}

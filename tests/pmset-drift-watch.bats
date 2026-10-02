#!/usr/bin/env bats
# Tests for the read-only pmset drift recorder.

load test_helper

WATCH_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-pmset-drift-watch"

setup() {
  TEST_DIR="$(mktemp -d)"
  export ORIG_HOME="$HOME"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export DOTFILES_PMSET_BIN="$TEST_DIR/pmset"
  LOG="$HOME/.local/share/dotfiles/logs/pmset-drift.log"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

stub_pmset() {
  local disksleep="$1"
  cat > "$DOTFILES_PMSET_BIN" << STUB
#!/bin/bash
case "\$2" in
  custom) printf 'AC Power:\n disksleep            %s\n' "$disksleep" ;;
  batt) echo "Now drawing from 'Battery Power'" ;;
esac
STUB
  chmod +x "$DOTFILES_PMSET_BIN"
}

@test "first run stores a baseline and logs nothing" {
  stub_pmset 10
  run bash "$WATCH_CMD"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/state/dotfiles/pmset-custom.last" ]
  [ ! -f "$LOG" ]
}

@test "unchanged settings log nothing" {
  stub_pmset 10
  bash "$WATCH_CMD"
  run bash "$WATCH_CMD"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "a change logs the diff, power source, and process snapshot" {
  stub_pmset 10
  bash "$WATCH_CMD"
  stub_pmset 0
  run bash "$WATCH_CMD"
  [ "$status" -eq 0 ]
  grep -q 'pmset settings changed' "$LOG"
  grep -q "power source: Now drawing from 'Battery Power'" "$LOG"
  grep -q '< *disksleep *10' "$LOG"
  grep -q '> *disksleep *0' "$LOG"
  grep -q 'processes started in the last 3 minutes' "$LOG"
  grep -q 'disksleep *0' "$HOME/.local/state/dotfiles/pmset-custom.last"
}

@test "script never writes power settings" {
  ! grep -Eq 'pmset" +-[abcu] |sudo' "$WATCH_CMD"
}

@test "LaunchAgent watches the power-management plist" {
  local plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.pmset-drift-watch.plist.tmpl"
  grep -q '<string>/Library/Preferences/com.apple.PowerManagement.plist</string>' "$plist"
  grep -q 'bin/dotfiles-pmset-drift-watch' "$plist"
}

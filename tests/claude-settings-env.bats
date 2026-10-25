#!/usr/bin/env bats
# Tests for .chezmoiscripts/run_after_claude-settings-env.sh — pins
# AGENT_GUARD_DEPTH_MAX=2 in ~/.claude/settings.json env.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.local/bin"
  touch "$HOME/.local/bin/claude"
  SCRIPT="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_claude-settings-env.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "writes AGENT_GUARD_DEPTH_MAX=2 when settings.json is missing" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.env.AGENT_GUARD_DEPTH_MAX' "$HOME/.claude/settings.json")" = "2" ]
}

@test "keeps other keys and other env values" {
  echo '{"model":"m","env":{"FOO":"bar","AGENT_GUARD_DEPTH_MAX":"1"}}' > "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.env.AGENT_GUARD_DEPTH_MAX' "$HOME/.claude/settings.json")" = "2" ]
  [ "$(jq -r '.env.FOO' "$HOME/.claude/settings.json")" = "bar" ]
  [ "$(jq -r '.model' "$HOME/.claude/settings.json")" = "m" ]
}

@test "is a no-op when the value is already set" {
  echo '{"env":{"AGENT_GUARD_DEPTH_MAX":"2"}}' > "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "skips when Claude Code is not installed" {
  rm "$HOME/.local/bin/claude"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/settings.json" ]
}

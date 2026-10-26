#!/usr/bin/env bats
# Tests for .chezmoiscripts/run_after_claude-settings-env.sh — pins
# AGENT_GUARD_DEPTH_MAX=2 and CLAUDE_CODE_AUTO_COMPACT_WINDOW=350000 in
# ~/.claude/settings.json env.

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
  echo '{"env":{"AGENT_GUARD_DEPTH_MAX":"2","CLAUDE_CODE_AUTO_COMPACT_WINDOW":"350000"}}' > "$HOME/.claude/settings.json"
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

@test "invalid JSON is refused and left byte-for-byte the same" {
  printf '{"env": {broken' > "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$TEST_DIR/before"
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to overwrite"* ]]
  cmp "$TEST_DIR/before" "$HOME/.claude/settings.json"
}

@test "an empty file gets the pin" {
  : > "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.env.AGENT_GUARD_DEPTH_MAX' "$HOME/.claude/settings.json")" = "2" ]
}

@test "file mode survives a rewrite" {
  echo '{}' > "$HOME/.claude/settings.json"
  chmod 640 "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$HOME/.claude/settings.json" 2>/dev/null || stat -c '%a' "$HOME/.claude/settings.json")" = "640" ]
}

@test "a symlink survives and its target gets the pin" {
  mkdir -p "$TEST_DIR/real"
  echo '{"a":1}' > "$TEST_DIR/real/settings.json"
  ln -s "$TEST_DIR/real/settings.json" "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/settings.json" ]
  [ "$(jq -r '.env.AGENT_GUARD_DEPTH_MAX' "$TEST_DIR/real/settings.json")" = "2" ]
  [ "$(jq -r '.a' "$TEST_DIR/real/settings.json")" = "1" ]
}

@test "running twice gives no change the second time" {
  echo '{"model":"m"}' > "$HOME/.claude/settings.json"
  bash "$SCRIPT"
  cp "$HOME/.claude/settings.json" "$TEST_DIR/once"
  run bash "$SCRIPT"
  [ -z "$output" ]
  cmp "$TEST_DIR/once" "$HOME/.claude/settings.json"
}

@test "non-string env values and other keys are kept" {
  echo '{"env":{"N":3,"B":true,"O":{"x":1}},"hooks":{"k":[1]}}' > "$HOME/.claude/settings.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.env.N, .env.B, .env.O, .hooks' "$HOME/.claude/settings.json" | tr '\n' ' ')" = '3 true {"x":1} {"k":[1]} ' ]
}

@test "--print-desired prints the pinned env" {
  run bash "$SCRIPT" --print-desired
  [ "$output" = '{"AGENT_GUARD_DEPTH_MAX":"2","CLAUDE_CODE_AUTO_COMPACT_WINDOW":"350000"}' ]
}

@test "writes the auto-compact window" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.env.CLAUDE_CODE_AUTO_COMPACT_WINDOW' "$HOME/.claude/settings.json")" = "350000" ]
}

@test "auto-compact runs at least 30k below the guard's tool-budget line" {
  # The guard refuses tool calls above AGENT_GUARD_TOOL_CONTEXT (default
  # 400000) when nobody can answer. Compaction must come first.
  want="$(bash "$SCRIPT" --print-desired)"
  window="$(printf '%s' "$want" | jq -r '.CLAUDE_CODE_AUTO_COMPACT_WINDOW | tonumber')"
  guard="$(printf '%s' "$want" | jq -r '.AGENT_GUARD_TOOL_CONTEXT // "400000" | tonumber')"
  [ "$window" -ge 100000 ]
  [ $((guard - window)) -ge 30000 ]
}

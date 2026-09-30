#!/usr/bin/env bats
# Tests for bin/dotfiles-agent-wake-recover

WAKE_BIN="$BATS_TEST_DIRNAME/../bin/dotfiles-agent-wake-recover"

@test "dotfiles-agent-wake-recover exists and is executable" {
  [ -x "$WAKE_BIN" ]
}

@test "dotfiles-agent-wake-recover valid bash syntax" {
  run bash -n "$WAKE_BIN"
  [ "$status" -eq 0 ]
}

@test "dotfiles-agent-wake-recover supports --dry-run and --quiet" {
  grep -q '\-\-dry-run' "$WAKE_BIN"
  grep -q '\-\-quiet' "$WAKE_BIN"
}

@test "dotfiles-agent-wake-recover invokes heal-stuck-agents --fix --quiet" {
  grep -q 'dotfiles-heal-stuck-agents' "$WAKE_BIN"
  grep -q '\-\-fix' "$WAKE_BIN"
  grep -q '\-\-quiet' "$WAKE_BIN"
}

@test "dotfiles-agent-wake-recover kicks network-resilience and agent-keepawake" {
  grep -q 'dotfiles_heal_kickstart_network_resilience' "$WAKE_BIN"
  grep -q 'dotfiles_agent_kickstart_keepawake_agent' "$WAKE_BIN"
}

@test "dotfiles-agent-wake-recover verifies CDP LaunchAgent labels" {
  grep -q 'com.dotfiles.agent-browser-chrome' "$WAKE_BIN"
  grep -q 'com.dotfiles.tooling-chrome' "$WAKE_BIN"
}

@test "dotfiles-agent-wake-recover does not run agentbrew status" {
  ! grep -q 'agentbrew status' "$WAKE_BIN"
}

@test "dotfiles-agent-wake-recover --dry-run exits 0" {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/.local/share/dotfiles/logs"
  run bash "$WAKE_BIN" --dry-run
  rm -rf "$TEST_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}

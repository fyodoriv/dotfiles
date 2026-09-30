#!/usr/bin/env bats
# Tests for snapshot.sh — macOS defaults snapshot/diff/list

load test_helper

SNAPSHOT_CMD="$BATS_TEST_DIRNAME/../snapshot.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export SNAPSHOT_DIR="$TEST_DIR/.dotfiles-snapshots"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ─────────────────────────────────────────────────

@test "snapshot.sh exists and is executable" {
  [ -f "$SNAPSHOT_CMD" ]
  [ -x "$SNAPSHOT_CMD" ]
}

@test "snapshot.sh has correct shebang" {
  head -1 "$SNAPSHOT_CMD" | grep -q '#!/bin/bash'
}

@test "snapshot.sh sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$SNAPSHOT_CMD"
}

@test "snapshot.sh sets strict mode" {
  grep -q 'set -euo pipefail' "$SNAPSHOT_CMD"
}

# ── Usage / help ──────────────────────────────────────────────────

@test "snapshot.sh without args shows usage and exits 1" {
  run "$SNAPSHOT_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "snapshot.sh with invalid flag shows usage" {
  run "$SNAPSHOT_CMD" --invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── --macos creates a snapshot ────────────────────────────────────

@test "snapshot --macos creates snapshot directory" {
  run "$SNAPSHOT_CMD" --macos
  [ "$status" -eq 0 ]
  [ -d "$SNAPSHOT_DIR" ]
}

@test "snapshot --macos creates timestamped file" {
  run "$SNAPSHOT_CMD" --macos
  [ "$status" -eq 0 ]
  local count
  count=$(ls "$SNAPSHOT_DIR"/macos-*.txt 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 1 ]
}

@test "snapshot --macos file contains domain headers" {
  run "$SNAPSHOT_CMD" --macos
  local file
  file=$(ls "$SNAPSHOT_DIR"/macos-*.txt | head -1)
  grep -q '=== NSGlobalDomain ===' "$file"
  grep -q '=== com.apple.dock ===' "$file"
  grep -q '=== com.apple.finder ===' "$file"
}

@test "snapshot --macos reports line count" {
  run "$SNAPSHOT_CMD" --macos
  [ "$status" -eq 0 ]
  [[ "$output" == *"lines"* ]]
}

# ── --list ────────────────────────────────────────────────────────

@test "snapshot --list with no snapshots shows info message" {
  run "$SNAPSHOT_CMD" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No snapshots"* ]]
}

@test "snapshot --list after snapshot shows file" {
  "$SNAPSHOT_CMD" --macos
  run "$SNAPSHOT_CMD" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"macos-"* ]]
}

# ── --diff ────────────────────────────────────────────────────────

@test "snapshot --diff without file shows error" {
  run "$SNAPSHOT_CMD" --diff
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "snapshot --diff with missing file shows error" {
  run "$SNAPSHOT_CMD" --diff /nonexistent/file.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "snapshot --diff against fresh snapshot succeeds" {
  "$SNAPSHOT_CMD" --macos
  local file
  file=$(ls "$SNAPSHOT_DIR"/macos-*.txt | head -1)
  run "$SNAPSHOT_CMD" --diff "$file"
  [ "$status" -eq 0 ]
}

# ── Domain coverage ───────────────────────────────────────────────

@test "snapshot.sh covers all critical macOS domains" {
  grep -q 'NSGlobalDomain' "$SNAPSHOT_CMD"
  grep -q 'com.apple.dock' "$SNAPSHOT_CMD"
  grep -q 'com.apple.finder' "$SNAPSHOT_CMD"
  grep -q 'com.apple.screencapture' "$SNAPSHOT_CMD"
  grep -q 'com.apple.TimeMachine' "$SNAPSHOT_CMD"
}

@test "snapshot.sh MACOS_DOMAINS array has 25+ entries" {
  local count
  count=$(grep -c '^\s\+com\.' "$SNAPSHOT_CMD" || true)
  # NSGlobalDomain + com.apple.* entries
  [ "$count" -ge 25 ]
}

@test "snapshot --macos is idempotent (second run creates new file)" {
  "$SNAPSHOT_CMD" --macos
  # Wait for timestamp to tick so the second file gets a distinct name
  local first_ts
  first_ts=$(date +%s)
  for _i in $(seq 1 20); do [ "$(date +%s)" -ne "$first_ts" ] && break; sleep 0.1; done
  "$SNAPSHOT_CMD" --macos
  local count
  count=$(ls "$SNAPSHOT_DIR"/macos-*.txt 2>/dev/null | wc -l | tr -d ' ')
  [ "$count" -eq 2 ]
}

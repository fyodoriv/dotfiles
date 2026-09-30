#!/usr/bin/env bats
# Tests for graceful-restart script

load test_helper

GRACEFUL_CMD="$BATS_TEST_DIRNAME/../bin/graceful-restart"

@test "graceful-restart script exists and is executable" {
  [ -f "$GRACEFUL_CMD" ]
  [ -x "$GRACEFUL_CMD" ]
}

@test "graceful-restart script has correct shebang" {
  head -1 "$GRACEFUL_CMD" | grep -q '#!/bin/bash'
}

@test "graceful-restart script uses strict mode" {
  grep -q 'set -euo pipefail' "$GRACEFUL_CMD"
}

@test "graceful-restart script sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$GRACEFUL_CMD"
}

@test "graceful-restart defines blocker patterns" {
  grep -q 'BLOCKERS=' "$GRACEFUL_CMD"
}

@test "graceful-restart checks for yarn, webpack, tsc, jest, vitest" {
  grep -q 'arn install' "$GRACEFUL_CMD"
  grep -q 'arn build' "$GRACEFUL_CMD"
  grep -q 'ebpack serve' "$GRACEFUL_CMD"
  grep -q 'sc --build' "$GRACEFUL_CMD"
  grep -q 'Jest tests' "$GRACEFUL_CMD"
  grep -q 'Vitest tests' "$GRACEFUL_CMD"
}

@test "graceful-restart checks for gradle, npm, git operations" {
  grep -q 'gradlew' "$GRACEFUL_CMD"
  grep -q 'pm install' "$GRACEFUL_CMD"
  grep -q 'Git rebase' "$GRACEFUL_CMD"
  grep -q 'Git merge' "$GRACEFUL_CMD"
}

@test "graceful-restart checks for dotfiles processes" {
  grep -q 'Dotfiles sync' "$GRACEFUL_CMD"
  grep -q 'Dotfiles doctor' "$GRACEFUL_CMD"
}

@test "graceful-restart excludes agent processes from blocker check" {
  grep -q 'cursor.agent\|claude-bg\|devin' "$GRACEFUL_CMD"
}

@test "graceful-restart detects dirty repos in ~/apps" {
  grep -q 'git -C.*status --porcelain' "$GRACEFUL_CMD"
  grep -q 'dirty_repos' "$GRACEFUL_CMD"
}

@test "graceful-restart supports --now flag to skip confirmation" {
  grep -q '\-\-now' "$GRACEFUL_CMD"
  grep -q 'read -r -t 30 answer' "$GRACEFUL_CMD"
}

@test "graceful-restart waits in a loop for blockers to finish" {
  grep -q 'while true' "$GRACEFUL_CMD"
  grep -q 'sleep 3' "$GRACEFUL_CMD"
}

@test "graceful-restart uses osascript to restart" {
  grep -q 'osascript.*restart' "$GRACEFUL_CMD"
}

@test "graceful-restart shows success when no blockers" {
  grep -q 'No blocking processes' "$GRACEFUL_CMD"
}

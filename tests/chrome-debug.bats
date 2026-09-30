#!/usr/bin/env bats
# Tests for the chrome-debug bin script — a wrapper around the
# com.dotfiles.chrome-debug LaunchAgent. We only test structure and help
# output; exercising start/stop would toggle the user's real LaunchAgent.

setup() {
  CHROME_DEBUG="$BATS_TEST_DIRNAME/../bin/chrome-debug"
}

@test "chrome-debug script exists and is executable" {
  [ -x "$CHROME_DEBUG" ]
}

@test "chrome-debug has bash shebang and strict mode" {
  head -1 "$CHROME_DEBUG" | grep -q '^#!/bin/bash'
  grep -q 'set -euo pipefail' "$CHROME_DEBUG"
}

@test "chrome-debug --help exits 0 and prints usage" {
  run "$CHROME_DEBUG" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"chrome-debug"* ]]
  [[ "$output" == *"--stop"* ]]
  [[ "$output" == *"--status"* ]]
}

@test "chrome-debug -h also exits 0 and prints usage" {
  run "$CHROME_DEBUG" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "chrome-debug references the LaunchAgent label" {
  grep -q 'com.dotfiles.chrome-debug' "$CHROME_DEBUG"
}

@test "chrome-debug references port 9222" {
  grep -q '9222' "$CHROME_DEBUG"
}

@test "chrome-debug handles --stop and --status subcommands" {
  grep -q -- '--stop' "$CHROME_DEBUG"
  grep -q -- '--status' "$CHROME_DEBUG"
}

@test "chrome-debug checks for plist presence before starting" {
  grep -q 'PLIST=.*LaunchAgents' "$CHROME_DEBUG"
  grep -q '! -f.*PLIST' "$CHROME_DEBUG"
}

@test "chrome-debug is idempotent when already running" {
  grep -q 'already running' "$CHROME_DEBUG"
}

@test "chrome-debug rejects unknown subcommands with exit 2" {
  run "$CHROME_DEBUG" bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "cheat sheet references chrome-debug command (not [port])" {
  CHEAT="$BATS_TEST_DIRNAME/../bin/cheat"
  grep -q '"chrome-debug"' "$CHEAT"
  grep -q '"chrome-debug --stop"' "$CHEAT"
  # The [port] arg was dropped — port is fixed by the LaunchAgent.
  ! grep -q 'chrome-debug \[port\]' "$CHEAT"
}

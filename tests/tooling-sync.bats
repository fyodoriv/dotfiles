#!/usr/bin/env bats
# Tests for bin/tooling-sync — argument parsing + dry-run safety.
# Pattern: thin CLI surface around a parallel-fetch loop. We test the
# arg parser and the rate-limit guard. Network paths are out of scope
# for unit tests (would require fixture remotes); the dry-run mode is
# the contract for "no side effects" verification.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/tooling-sync"

setup() {
  TEST_DIR="$(mktemp -d)"
  export XDG_DATA_HOME="$TEST_DIR/xdg"
  mkdir -p "$XDG_DATA_HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "tooling-sync --help prints usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"tooling-sync"* ]]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "tooling-sync -h is equivalent to --help" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"tooling-sync"* ]]
}

@test "tooling-sync rejects unknown arguments with exit 64" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 64 ]
  [[ "$output" == *"unknown argument: --bogus"* ]]
}

@test "tooling-sync --dry-run never writes the stamp file" {
  rm -f "$XDG_DATA_HOME/tooling-sync/last-run"
  run "$SCRIPT" --dry-run --force
  [ "$status" -eq 0 ]
  [ ! -f "$XDG_DATA_HOME/tooling-sync/last-run" ]
}

@test "tooling-sync without --force respects the rate-limit stamp" {
  mkdir -p "$XDG_DATA_HOME/tooling-sync"
  # Stamp = now (so rate limit not yet expired).
  date +%s > "$XDG_DATA_HOME/tooling-sync/last-run"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  # No log appended because we exited before the work loop.
  [ ! -s "$XDG_DATA_HOME/tooling-sync/sync.log" ]
}

@test "tooling-sync --force ignores the rate-limit stamp" {
  mkdir -p "$XDG_DATA_HOME/tooling-sync"
  date +%s > "$XDG_DATA_HOME/tooling-sync/last-run"
  # --force --dry-run together: bypasses rate limit AND skips real I/O.
  # Should print the dry-run header.
  run "$SCRIPT" --force --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== tooling-sync start (dry-run=1 force=1) ==="* ]]
}

@test "tooling-sync writes the stamp on a real run (no --dry-run)" {
  rm -f "$XDG_DATA_HOME/tooling-sync/last-run"
  # Real run with --force so we don't depend on rate-limit state.
  # The script will attempt git operations against ~/apps/tooling/* dirs —
  # in CI those may not exist, which is fine (sync_repo handles SKIP).
  run "$SCRIPT" --force
  [ "$status" -eq 0 ]
  [ -f "$XDG_DATA_HOME/tooling-sync/last-run" ]
}

@test "tooling-sync help body mentions the origin-only push privacy rule" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  # The doc header documents that this script pushes only to 'origin'
  # and that the global pre-push hook runs the privacy gate.
  [[ "$output" == *"origin"* ]]
  [[ "$output" == *"pre-push"* ]]
}

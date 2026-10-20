#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-lock-checked"

setup() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUB_DIR"
  COUNT="$STUB_DIR/count"
  : > "$COUNT"
}

teardown() {
  rm -rf "$STUB_DIR"
}

# stub_cmd <name> <body>: write an executable stub that logs each call.
stub_cmd() {
  printf '#!/bin/bash\necho x >> "%s"\n%s\n' "$COUNT" "$2" > "$STUB_DIR/$1"
  chmod +x "$STUB_DIR/$1"
}

@test "passes through a clean run with its exit code 0" {
  stub_cmd ok 'echo "applied 3 files"'
  run "$SCRIPT" --wait 0 -- "$STUB_DIR/ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied 3 files"* ]]
}

@test "keeps the exit code of a failed command without retry" {
  stub_cmd bad 'echo boom; exit 3'
  run "$SCRIPT" --wait 0 -- "$STUB_DIR/bad"
  [ "$status" -eq 3 ]
  [ "$(wc -l < "$COUNT" | tr -d ' ')" -eq 1 ]
}

@test "lock skip with exit 0 is reported as not applied" {
  stub_cmd skip 'echo "[lock] Skipping — locked by upgrade (pid 9) — fix: wait"; exit 0'
  run "$SCRIPT" --wait 0 --retries 2 -- "$STUB_DIR/skip"
  [ "$status" -eq 75 ]
  [[ "$output" == *"not applied"* ]]
  [ "$(wc -l < "$COUNT" | tr -d ' ')" -eq 3 ]
}

@test "lock timeout with exit 0 is reported as not applied" {
  stub_cmd tmo 'echo "[lock] Timed out after 120s — still locked by upgrade (pid 9)"'
  run "$SCRIPT" --wait 0 --retries 0 -- "$STUB_DIR/tmo"
  [ "$status" -eq 75 ]
  [[ "$output" == *"not applied"* ]]
}

@test "re-runs after a lock skip and succeeds when the lock frees" {
  stub_cmd flaky '[ "$(wc -l < "'"$COUNT"'")" -ge 2 ] && { echo done; exit 0; }; echo "[lock] Skipping — locked by upgrade"'
  run "$SCRIPT" --wait 0 --retries 3 -- "$STUB_DIR/flaky"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
  [ "$(wc -l < "$COUNT" | tr -d ' ')" -eq 2 ]
}

@test "--log: lock skip without Summary means did not run" {
  printf '[lock] Skipping — locked by apply\n' > "$STUB_DIR/up.log"
  run "$SCRIPT" --log "$STUB_DIR/up.log"
  [ "$status" -eq 75 ]
  [[ "$output" == *"did not run"* ]]
}

@test "--log: a log with a Summary section ran" {
  printf 'lots\n── Summary ──\nBrew: OK\n' > "$STUB_DIR/up.log"
  run "$SCRIPT" --log "$STUB_DIR/up.log"
  [ "$status" -eq 0 ]
}

@test "--log: a missing log means did not run" {
  run "$SCRIPT" --log "$STUB_DIR/nope.log"
  [ "$status" -eq 75 ]
}

@test "usage error without a command" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

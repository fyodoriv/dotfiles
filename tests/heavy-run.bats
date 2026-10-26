#!/usr/bin/env bats
# Tests for bin/heavy-run — one heavy command at a time, at low priority.

SCRIPT="$BATS_TEST_DIRNAME/../bin/heavy-run"

setup() {
  export HEAVY_RUN_DIR="$BATS_TEST_TMPDIR/hr"
}

@test "heavy-run: runs the command and returns its exit status" {
  run "$SCRIPT" sh -c 'echo hi; exit 3'
  [ "$status" -eq 3 ]
  [ "$output" = "hi" ]
}

@test "heavy-run: lowers priority by HEAVY_RUN_NICE" {
  base=$(ps -o nice= -p $$ | tr -d ' ')
  [ "$base" -le 15 ] || skip "caller already at nice $base"
  HEAVY_RUN_NICE=4 run "$SCRIPT" sh -c 'ps -o nice= -p $$'
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" = "$((base + 4))" ]
}

@test "heavy-run: two runs never overlap" {
  log="$BATS_TEST_TMPDIR/order"
  "$SCRIPT" sh -c "echo start1 >>'$log'; sleep 1; echo end1 >>'$log'" &
  sleep 0.3
  "$SCRIPT" sh -c "echo start2 >>'$log'; echo end2 >>'$log'"
  wait
  run cat "$log"
  [ "${lines[0]}" = "start1" ]
  [ "${lines[1]}" = "end1" ]
  [ "${lines[2]}" = "start2" ]
}

@test "heavy-run: --status names the holder, then free" {
  "$SCRIPT" sleep 1 &
  sleep 0.4
  run "$SCRIPT" --status
  [[ "$output" == held:*"cmd=sleep 1"* ]]
  wait
  run "$SCRIPT" --status
  [ "$output" = "free" ]
}

@test "heavy-run: no arguments prints usage and exits 2" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == Usage:* ]]
}

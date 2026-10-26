#!/usr/bin/env bats
# Tests for bin/heavy-run — one heavy command at a time, at low priority.

SCRIPT="$BATS_TEST_DIRNAME/../bin/heavy-run"

setup() {
  export HEAVY_RUN_DIR="$BATS_TEST_TMPDIR/hr"
  unset HEAVY_RUN_HELD
}

# Wait up to 5 s for the first run to hold the lock.
wait_held() {
  local i
  for i in $(seq 50); do
    [ -s "$HEAVY_RUN_DIR/owner" ] && return 0
    sleep 0.1
  done
  return 1
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
  wait_held
  "$SCRIPT" sh -c "echo start2 >>'$log'; echo end2 >>'$log'"
  wait
  run cat "$log"
  [ "${lines[0]}" = "start1" ]
  [ "${lines[1]}" = "end1" ]
  [ "${lines[2]}" = "start2" ]
  [ "${lines[3]}" = "end2" ]
}

@test "heavy-run: SIGTERM to the wrapper stops the command and frees the lock only then" {
  log="$BATS_TEST_TMPDIR/order"
  "$SCRIPT" sh -c "trap 'echo term1 >>\"$log\"; exit 143' TERM; echo start1 >>'$log'; sleep 5 & wait" &
  pid=$!
  for i in $(seq 50); do grep -q start1 "$log" 2>/dev/null && break; sleep 0.1; done
  kill -TERM "$pid"
  "$SCRIPT" sh -c "echo start2 >>'$log'"
  wait "$pid" || true
  run cat "$log"
  [ "${lines[0]}" = "start1" ]
  [ "${lines[1]}" = "term1" ]
  [ "${lines[2]}" = "start2" ]
}

@test "heavy-run: --status names the holder, then free" {
  "$SCRIPT" sleep 1 &
  wait_held
  run "$SCRIPT" --status
  [[ "$output" == held:*"cmd=sleep 1"* ]]
  wait
  run "$SCRIPT" --status
  [ "$output" = "free" ]
}

@test "heavy-run: --status ignores an owner line whose pid is gone" {
  mkdir -p "$HEAVY_RUN_DIR"
  sh -c 'exit 0' & dead=$!
  wait "$dead"
  echo "10:00:00 pid=$dead cwd=/x cmd=old" >"$HEAVY_RUN_DIR/owner"
  run "$SCRIPT" --status
  [ "$output" = "free" ]
}

@test "heavy-run: a nested call runs at once and keeps the outer owner line" {
  run "$SCRIPT" sh -c "'$SCRIPT' sh -c 'echo inner'; '$SCRIPT' --status"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "inner" ]
  [[ "${lines[1]}" == held:* ]]
}

@test "heavy-run: rejects a bad HEAVY_RUN_NICE" {
  HEAVY_RUN_NICE=x run "$SCRIPT" true
  [ "$status" -eq 2 ]
  [[ "$output" == *HEAVY_RUN_NICE* ]]
}

@test "heavy-run: no arguments prints usage and exits 2; --help exits 0" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == Usage:* ]]
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

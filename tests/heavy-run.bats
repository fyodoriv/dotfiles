#!/usr/bin/env bats
# Tests for bin/heavy-run — one heavy command at a time, at low priority.

SCRIPT="$BATS_TEST_DIRNAME/../bin/heavy-run"

bats_require_minimum_version 1.5.0

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
  run --separate-stderr "$SCRIPT" sh -c 'echo hi; exit 3'
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
  run --separate-stderr "$SCRIPT" sh -c "'$SCRIPT' sh -c 'echo inner'; '$SCRIPT' --status"
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

@test "heavy-run: a leftover background child does not keep the lock" {
  "$SCRIPT" sh -c '(sleep 4 &) ; exit 0'
  start=$(date +%s)
  "$SCRIPT" true
  [ $(( $(date +%s) - start )) -lt 3 ]
  run "$SCRIPT" --status
  [ "$output" = "free" ]
}

@test "heavy-run: a command that starts with a dash is not a nice option" {
  run -127 --separate-stderr "$SCRIPT" -n 5 true
}

@test "heavy-run: rejects HEAVY_RUN_NICE above 20" {
  HEAVY_RUN_NICE=25 run "$SCRIPT" true
  [ "$status" -eq 2 ]
}

@test "heavy-run: a stale HEAVY_RUN_HELD does not skip a free lock" {
  mkdir -p "$HEAVY_RUN_DIR"
  HEAVY_RUN_HELD="$HEAVY_RUN_DIR/lock" run "$SCRIPT" sh -c "'$SCRIPT' --status"
  [[ "$output" == held:* ]]
}

# Wait up to 5 s until --status lists $1 live queue entries.
wait_queued() {
  local i
  for i in $(seq 50); do
    [ "$("$SCRIPT" --status | grep -c '^queue ')" -ge "$1" ] && return 0
    sleep 0.1
  done
  return 1
}

# Hold a live ticket (an flock on its file) without taking the lock; the pid
# is $FAKE_PID. $1 is the ticket number. Stop it with: kill "$FAKE_PID".
fake_live_ticket() {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  perl -e 'use Fcntl ":flock"; open(F, ">>", "$ARGV[0]-$$") or die; flock(F, LOCK_EX) or die; print F "pid=$$ cwd=/x cmd=fake\n"; close STDOUT; sleep 30' "$HEAVY_RUN_DIR/queue/$1" &
  FAKE_PID=$!
  sleep 0.5
}

@test "heavy-run: three waiters run in arrival order behind a holder" {
  log="$BATS_TEST_TMPDIR/fifo"
  "$SCRIPT" sleep 2 &
  wait_held
  for n in A B C; do
    "$SCRIPT" sh -c "echo $n >>'$log'" &
    wait_queued $(( $(printf '%d' "'$n") - 64 ))
  done
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "queue 1: "*"echo A"* ]]
  [[ "${lines[2]}" == "queue 2: "*"echo B"* ]]
  [[ "${lines[3]}" == "queue 3: "*"echo C"* ]]
  wait
  run cat "$log"
  [ "${lines[0]}" = "A" ]
  [ "${lines[1]}" = "B" ]
  [ "${lines[2]}" = "C" ]
}

@test "heavy-run: a dead waiter's ticket does not block the queue and is removed" {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  sh -c 'exit 0' & dead=$!
  wait "$dead"
  echo "pid=$dead cwd=/x cmd=ghost" >"$HEAVY_RUN_DIR/queue/0000000000-$dead"
  run timeout 10 "$SCRIPT" echo ran
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
  [ ! -e "$HEAVY_RUN_DIR/queue/0000000000-$dead" ]
}

@test "heavy-run: --status lists the queue in order" {
  "$SCRIPT" sleep 2 &
  wait_held
  "$SCRIPT" sh -c "echo first" &
  wait_queued 1
  "$SCRIPT" sh -c "echo second" &
  wait_queued 2
  run "$SCRIPT" --status
  [[ "${lines[0]}" == held:* ]]
  [[ "${lines[1]}" == "queue 1: "*"echo first"* ]]
  [[ "${lines[2]}" == "queue 2: "*"echo second"* ]]
  wait
}

@test "heavy-run: a waiter stopped by SIGTERM removes its own ticket" {
  "$SCRIPT" sleep 2 &
  wait_held
  "$SCRIPT" true &
  pid=$!
  wait_queued 1
  kill -TERM "$pid"
  rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 143 ]
  [ -z "$(ls "$HEAVY_RUN_DIR/queue")" ]
  wait
}

@test "heavy-run: a waiter stopped by SIGINT exits 130 and by SIGHUP exits 129" {
  "$SCRIPT" sleep 3 &
  wait_held
  "$SCRIPT" true & pid=$!
  wait_queued 1
  kill -INT "$pid"
  rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 130 ]
  "$SCRIPT" true & pid=$!
  wait_queued 1
  kill -HUP "$pid"
  rc=0; wait "$pid" || rc=$?
  [ "$rc" -eq 129 ]
  wait
}

@test "heavy-run: each run appends a waited=<seconds> line to the wait log" {
  "$SCRIPT" true
  "$SCRIPT" true
  run cat "$HEAVY_RUN_DIR/waits.log"
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" =~ waited=[0-9]+ ]]
}

@test "heavy-run: HEAVY_RUN_WAIT_LOG moves the wait log" {
  HEAVY_RUN_WAIT_LOG="$BATS_TEST_TMPDIR/w.log" "$SCRIPT" true
  grep -q 'waited=' "$BATS_TEST_TMPDIR/w.log"
  [ ! -e "$HEAVY_RUN_DIR/waits.log" ]
}

@test "heavy-run: a ticket of a reused or foreign pid does not block the queue" {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  echo "pid=1 cwd=/x cmd=ghost" >"$HEAVY_RUN_DIR/queue/0000000000-1"
  run timeout 10 "$SCRIPT" echo ran
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
  [ ! -e "$HEAVY_RUN_DIR/queue/0000000000-1" ]
}

@test "heavy-run: a SIGKILLed waiter does not block the queue" {
  "$SCRIPT" sleep 2 &
  wait_held
  "$SCRIPT" echo victim &
  victim=$!
  wait_queued 1
  kill -KILL "$victim"
  wait "$victim" 2>/dev/null || true
  run timeout 15 "$SCRIPT" echo after
  [ "$status" -eq 0 ]
  [ "$output" = "after" ]
  [ -z "$(ls "$HEAVY_RUN_DIR/queue")" ]
  wait
}

@test "heavy-run: a live queue behind a free lock does not make a stale HEAVY_RUN_HELD skip the lock" {
  fake_live_ticket 9999999999
  HEAVY_RUN_HELD="$HEAVY_RUN_DIR/lock" run "$SCRIPT" sh -c "'$SCRIPT' --status"
  kill "$FAKE_PID"
  [[ "${lines[0]}" == held:* ]]
}

@test "heavy-run: --status skips a ticket nobody holds" {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  echo "pid=1 cwd=/x cmd=ghost" >"$HEAVY_RUN_DIR/queue/0000000000-1"
  run "$SCRIPT" --status
  [ "$output" = "free" ]
}

@test "heavy-run: an unusable queue folder warns once and falls back to the plain lock" {
  mkdir -p "$HEAVY_RUN_DIR"
  : >"$HEAVY_RUN_DIR/queue"
  run --separate-stderr "$SCRIPT" echo ran
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
  [[ "$stderr" == *"heavy-run: queue unavailable"* ]]
}

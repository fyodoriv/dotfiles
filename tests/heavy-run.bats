#!/usr/bin/env bats
# Tests for bin/heavy-run — heavy commands in shared slots (one by default), at low priority.
# Most tests pin one slot (the old single-lock behavior); the slot tests set more.

SCRIPT="$BATS_TEST_DIRNAME/../bin/heavy-run"

bats_require_minimum_version 1.5.0

setup() {
  export HEAVY_RUN_DIR="$BATS_TEST_TMPDIR/hr"
  # A scratch HOME keeps the real heavy_run_* settings out; a probe that
  # prints nothing means memory is fine, so tests do not depend on this Mac.
  export HOME="$BATS_TEST_TMPDIR/home" HEAVY_RUN_SLOTS=1 HEAVY_RUN_RAMP=0 HEAVY_RUN_PROBE=true
  # No real-time app holds the tests, even while one runs on this Mac.
  export HEAVY_RUN_PAUSE_APPS=""
  unset XDG_CONFIG_HOME HEAVY_RUN_MAX_LOAD
  unset HEAVY_RUN_HELD FIFO_RELEASE
}

teardown() {
  if [ -n "${FIFO_RELEASE:-}" ]; then
    release_fifo_holder
    wait
  fi
}

# Wait up to 5 s until $1 runs (default 1) hold a slot.
wait_held() {
  local i
  for i in $(seq 50); do
    [ "$("$SCRIPT" --status | grep -c "^slot ")" -ge "${1:-1}" ] && return 0
    sleep 0.1
  done
  return 1
}

@test "heavy-run: runs the command and returns its exit status" {
  run --separate-stderr "$SCRIPT" sh -c 'echo hi; exit 3'
  [ "$status" -eq 3 ]
  [ "$output" = "hi" ]
}

priority_fixture() {
  local fixture="$BATS_TEST_TMPDIR/priority"
  mkdir -p "$fixture"
  cat > "$fixture/HeavyPriorityFixture.pm" <<'PERL'
package HeavyPriorityFixture;
BEGIN {
  *CORE::GLOBAL::getpriority = sub { return 0 + $ENV{FIXTURE_NICE} };
  *CORE::GLOBAL::setpriority = sub {
    die "priority increase attempted\n" if $_[2] < $ENV{FIXTURE_NICE};
    $ENV{FIXTURE_NICE} = $_[2];
    return 1;
  };
}
1;
PERL
  cat > "$fixture/nice" <<'SH'
#!/bin/sh
[ "$1" = -n ] || exit 99
FIXTURE_NICE=$((FIXTURE_NICE + $2))
[ "$FIXTURE_NICE" -le 20 ] || FIXTURE_NICE=20
export FIXTURE_NICE
shift 2
[ "$1" != -- ] || shift
exec "$@"
SH
  chmod +x "$fixture/nice"
  export PATH="$fixture:$PATH" PERL5LIB="$fixture" PERL5OPT=-MHeavyPriorityFixture
}

@test "heavy-run: absolute priority reaches 15 from inherited 0" {
  priority_fixture
  FIXTURE_NICE=0 run "$SCRIPT" sh -c 'echo "$FIXTURE_NICE"'
  [ "$status" -eq 0 ]
  [ "$output" = 15 ]
}

@test "heavy-run: absolute priority reaches 15 from inherited 10" {
  priority_fixture
  FIXTURE_NICE=10 run "$SCRIPT" sh -c 'echo "$FIXTURE_NICE"'
  [ "$status" -eq 0 ]
  [ "$output" = 15 ]
}

@test "heavy-run: absolute priority stays 15 from inherited 15" {
  priority_fixture
  FIXTURE_NICE=15 run "$SCRIPT" sh -c 'echo "$FIXTURE_NICE"'
  [ "$status" -eq 0 ]
  [ "$output" = 15 ]
}

@test "heavy-run: absolute priority rejects inherited 20 without running command" {
  priority_fixture
  FIXTURE_NICE=20 run "$SCRIPT" touch "$BATS_TEST_TMPDIR/ran"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot raise priority"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
}

@test "heavy-run: absolute priority honors a configured target" {
  priority_fixture
  FIXTURE_NICE=10 HEAVY_RUN_NICE=18 run "$SCRIPT" sh -c 'echo "$FIXTURE_NICE"'
  [ "$status" -eq 0 ]
  [ "$output" = 18 ]
}

@test "heavy-run: absolute priority applies configured nested targets without waiting" {
  priority_fixture
  FIXTURE_NICE=10 run "$SCRIPT" sh -c 'HEAVY_RUN_NICE=18 "$1" sh -c '\''echo "$FIXTURE_NICE"'\''; echo "$FIXTURE_NICE"' sh "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = $'18\n15' ]
}

@test "heavy-run: absolute priority is 15 for a real command" {
  run "$SCRIPT" perl -e 'print getpriority(0, 0), "\n"'
  [ "$status" -eq 0 ]
  [ "$output" = 15 ]
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
  [ "${lines[0]}" = "busy: 1/1 slots" ]
  [[ "${lines[1]}" == "slot 1: "*"cmd=sleep 1"* ]]
  wait
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
}

@test "heavy-run: --status ignores an owner line whose pid is gone" {
  mkdir -p "$HEAVY_RUN_DIR"
  sh -c 'exit 0' & dead=$!
  wait "$dead"
  echo "10:00:00 pid=$dead cwd=/x cmd=old" >"$HEAVY_RUN_DIR/owner"
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
}

@test "heavy-run: a nested call runs at once and keeps the outer owner line" {
  run --separate-stderr "$SCRIPT" sh -c "'$SCRIPT' sh -c 'echo inner'; '$SCRIPT' --status"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "inner" ]
  [[ "${lines[1]}" == busy:* ]]
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
  [ "$output" = "free: 0/1 slots busy" ]
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
  [[ "$output" == busy:* ]]
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

# The 60-second alarm only bounds an abandoned fixture, not queue acceptance.
start_fifo_holder() {
  FIFO_RELEASE="$BATS_TEST_TMPDIR/release-holder"
  "$SCRIPT" perl -e 'alarm 60; until (-e $ARGV[0]) { select undef, undef, undef, 0.1 }' "$FIFO_RELEASE" &
}

release_fifo_holder() {
  : > "$FIFO_RELEASE"
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
  start_fifo_holder
  wait_held
  for n in A B C; do
    "$SCRIPT" sh -c "echo $n >>'$log'" &
    wait_queued $(( $(printf '%d' "'$n") - 64 ))
  done
  run "$SCRIPT" --status
  [[ "${lines[2]}" == "queue 1: "*"echo A"* ]]
  [[ "${lines[3]}" == "queue 2: "*"echo B"* ]]
  [[ "${lines[4]}" == "queue 3: "*"echo C"* ]]
  release_fifo_holder
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
  start_fifo_holder
  wait_held
  "$SCRIPT" sh -c "echo first" &
  wait_queued 1
  "$SCRIPT" sh -c "echo second" &
  wait_queued 2
  run "$SCRIPT" --status
  [[ "${lines[0]}" == busy:* ]]
  [[ "${lines[2]}" == "queue 1: "*"echo first"* ]]
  [[ "${lines[3]}" == "queue 2: "*"echo second"* ]]
  release_fifo_holder
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
  [[ "${lines[0]}" == busy:* ]]
}

@test "heavy-run: --status skips a ticket nobody holds" {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  echo "pid=1 cwd=/x cmd=ghost" >"$HEAVY_RUN_DIR/queue/0000000000-1"
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
}

@test "heavy-run: an unusable queue folder warns once and falls back to the plain lock" {
  mkdir -p "$HEAVY_RUN_DIR"
  : >"$HEAVY_RUN_DIR/queue"
  run --separate-stderr "$SCRIPT" echo ran
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
  [[ "$stderr" == *"heavy-run: queue unavailable"* ]]
}

@test "heavy-run: a wait log folder that cannot be made does not stop the command" {
  : >"$BATS_TEST_TMPDIR/afile"
  HEAVY_RUN_WAIT_LOG="$BATS_TEST_TMPDIR/afile/sub/waits.log" run "$SCRIPT" echo ran
  [ "$status" -eq 0 ]
  [ "$output" = "ran" ]
}

@test "heavy-run: an emptied seq file cannot jump the queue" {
  fake_live_ticket 0000000005
  : >"$HEAVY_RUN_DIR/seq"
  marker="$BATS_TEST_TMPDIR/ran"
  "$SCRIPT" sh -c "echo x >'$marker'" &
  waiter=$!
  sleep 1.5
  [ ! -e "$marker" ]
  kill "$FAKE_PID"
  wait "$waiter"
  [ -e "$marker" ]
}

@test "heavy-run: the sweep removes a stale temp ticket nobody holds" {
  mkdir -p "$HEAVY_RUN_DIR/queue"
  echo "pid=1" >"$HEAVY_RUN_DIR/queue/.new-424242"
  touch -t 202001010000 "$HEAVY_RUN_DIR/queue/.new-424242"
  "$SCRIPT" true
  [ -z "$(ls -A "$HEAVY_RUN_DIR/queue")" ]
}

# --- Slots: several runs at once, exclusive runs, and machine checks ---

RELEASE_ALL=""

# Start a run that holds its slot until $BATS_TEST_TMPDIR/release exists.
# Extra arguments go before the command (for example --exclusive).
start_holder() {
  RELEASE_ALL="$BATS_TEST_TMPDIR/release"
  "$SCRIPT" "$@" perl -e 'alarm 60; until (-e $ARGV[0]) { select undef, undef, undef, 0.05 }' "$RELEASE_ALL" &
}

release_all() {
  : > "$RELEASE_ALL"
  wait
}

@test "heavy-run: slots: three runs share three slots at once, a fourth waits for a free slot" {
  export HEAVY_RUN_SLOTS=3
  start_holder; start_holder; start_holder
  wait_held 3
  marker="$BATS_TEST_TMPDIR/fourth"
  "$SCRIPT" touch "$marker" &
  wait_queued 1
  run "$SCRIPT" --status
  [ "${lines[0]}" = "busy: 3/3 slots" ]
  [[ "${lines[4]}" == "queue 1: "*"(waiting: no free slot (3/3 busy))" ]]
  [ ! -e "$marker" ]
  release_all
  [ -e "$marker" ]
}

@test "heavy-run: slots: each run sees its own HEAVY_RUN_SLOT" {
  export HEAVY_RUN_SLOTS=2
  start_holder
  wait_held 1
  run "$SCRIPT" sh -c 'echo "$HEAVY_RUN_SLOT"'
  release_all
  [ "$output" = 2 ]
}

@test "heavy-run: slots: --exclusive waits for running runs, then blocks later runs" {
  export HEAVY_RUN_SLOTS=4
  log="$BATS_TEST_TMPDIR/order"
  start_holder
  wait_held 1
  "$SCRIPT" --exclusive sh -c "echo excl-start >>'$log'; sleep 1; echo excl-end >>'$log'" &
  wait_queued 1
  "$SCRIPT" sh -c "echo after >>'$log'" &
  wait_queued 2
  run "$SCRIPT" --status
  [[ "${lines[2]}" == "queue 1: "*"[exclusive] (waiting: exclusive: waiting for 1 running run(s) to end)" ]]
  [[ "${lines[3]}" == "queue 2: "*"(waiting: behind queue 1)" ]]
  [ ! -e "$log" ]
  : > "$RELEASE_ALL"
  for i in $(seq 50); do grep -q excl-start "$log" 2>/dev/null && break; sleep 0.1; done
  run "$SCRIPT" --status
  [[ "${lines[0]}" == "exclusive: "*"echo excl-start"* ]]
  wait
  run cat "$log"
  [ "${lines[0]}" = "excl-start" ]
  [ "${lines[1]}" = "excl-end" ]
  [ "${lines[2]}" = "after" ]
}

@test "heavy-run: slots: a normal run waits while an exclusive run is active" {
  export HEAVY_RUN_SLOTS=4
  start_holder --exclusive
  for i in $(seq 50); do "$SCRIPT" --status | grep -q '^exclusive: ' && break; sleep 0.1; done
  "$SCRIPT" true &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "queue 1: "*"(waiting: an exclusive run is active)" ]]
  release_all
  run "$SCRIPT" --status
  [ "$output" = "free: 0/4 slots busy" ]
}

@test "heavy-run: slots: a SIGKILLed run frees its slot at once" {
  export HEAVY_RUN_SLOTS=1
  "$SCRIPT" sleep 30 &
  victim=$!
  wait_held 1
  child=$(sed -n 's/.* pid=\([0-9]*\) .*/\1/p' "$HEAVY_RUN_DIR/slots/1.owner")
  kill -KILL "$victim"
  wait "$victim" 2>/dev/null || true
  run timeout 10 "$SCRIPT" echo after
  kill "$child" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$output" = "after" ]
}

@test "heavy-run: slots: a leftover slot owner line from a dead run reads as free" {
  mkdir -p "$HEAVY_RUN_DIR/slots"
  : >"$HEAVY_RUN_DIR/slots/1"
  echo "10:00:00 pid=1 cwd=/x cmd=ghost" >"$HEAVY_RUN_DIR/slots/1.owner"
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
  run "$SCRIPT" echo ran
  [ "$output" = "ran" ]
}

@test "heavy-run: slots: memory pressure holds extra runs but never the first" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_PROBE="test -e '$BATS_TEST_TMPDIR/pressure' && echo memory pressure warn"
  : >"$BATS_TEST_TMPDIR/pressure"
  start_holder
  wait_held 1
  marker="$BATS_TEST_TMPDIR/second"
  "$SCRIPT" touch "$marker" &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "${lines[2]}" == "queue 1: "*"(waiting: memory pressure warn)" ]]
  [ ! -e "$marker" ]
  rm "$BATS_TEST_TMPDIR/pressure"
  for i in $(seq 50); do [ -e "$marker" ] && break; sleep 0.1; done
  [ -e "$marker" ]
  release_all
}

@test "heavy-run: slots: the ramp spaces out run starts" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_RAMP=30
  start_holder
  wait_held 1
  "$SCRIPT" true &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "${lines[2]}" == *"(waiting: ramp: last run started "*"s ago, next after 30s)" ]]
  release_all
}

@test "heavy-run: slots: HEAVY_RUN_MAX_LOAD holds extra runs above the load" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_MAX_LOAD=0.0001
  start_holder
  wait_held 1
  "$SCRIPT" true &
  wait_queued 1
  run "$SCRIPT" --status
  release_all
  # An idle CI box can show load 0.00; then no wait is a pass too.
  [[ "${lines[2]}" == *"(waiting: load "*" above 0.0001)" ]] || [ "${#lines[@]}" -le 2 ]
}

@test "heavy-run: slots: the heavy_run_slots setting sets the count; env wins" {
  unset HEAVY_RUN_SLOTS
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_slots: 3\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  run "$SCRIPT" --status
  [ "$output" = "free: 0/3 slots busy" ]
  HEAVY_RUN_SLOTS=2 run "$SCRIPT" --status
  [ "$output" = "free: 0/2 slots busy" ]
}

@test "heavy-run: slots: a raised heavy_run_slots reaches a run already waiting" {
  unset HEAVY_RUN_SLOTS
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_slots: 1\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  start_holder
  wait_held 1
  marker="$BATS_TEST_TMPDIR/second"
  "$SCRIPT" touch "$marker" &
  wait_queued 1
  sleep 0.5
  [ ! -e "$marker" ]
  printf 'data:\n  heavy_run_slots: 2\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  for i in $(seq 50); do [ -e "$marker" ] && break; sleep 0.1; done
  [ -e "$marker" ]
  release_all
}

@test "heavy-run: slots: the default is one slot, whatever the machine size" {
  # 2026-11-01: an automatic 4 slots let several suites and builds run at once, and the owner's Mac froze twice.
  unset HEAVY_RUN_SLOTS
  run "$SCRIPT" --status
  [ "$output" = "free: 0/1 slots busy" ]
}

@test "heavy-run: slots: a setting with a trailing comment is still read" {
  unset HEAVY_RUN_SLOTS
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_slots: 2  # two at once\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  run "$SCRIPT" --status
  [ "$output" = "free: 0/2 slots busy" ]
}

@test "heavy-run: slots: rejects a bad HEAVY_RUN_SLOTS, HEAVY_RUN_RAMP or HEAVY_RUN_MAX_LOAD" {
  for v in 0 65 x -1; do
    HEAVY_RUN_SLOTS=$v run "$SCRIPT" true
    [ "$status" -eq 2 ]
    [[ "$output" == *HEAVY_RUN_SLOTS* ]]
  done
  HEAVY_RUN_RAMP=x run "$SCRIPT" true
  [ "$status" -eq 2 ]
  HEAVY_RUN_MAX_LOAD=1.2.3 run "$SCRIPT" true
  [ "$status" -eq 2 ]
}

@test "heavy-run: slots: --exclusive with no command prints usage and exits 2" {
  run "$SCRIPT" --exclusive
  [ "$status" -eq 2 ]
  [[ "$output" == Usage:* ]]
}

# A stand-in real-time app with its own process name (pgrep -x matches it).
# Each test gets its own name, so a leftover app never holds another test.
make_fake_app() {
  command -v cc >/dev/null || skip "needs a C compiler"
  APP="fake-game-$$-$BATS_TEST_NUMBER"
  printf '#include <unistd.h>\nint main(void){sleep(%s);return 0;}\n' "$1" | cc -x c - -o "$BATS_TEST_TMPDIR/$APP"
  export HEAVY_RUN_PAUSE_APPS="$APP"
}

@test "heavy-run: realtime: no run starts while a listed app runs" {
  make_fake_app 30
  "$BATS_TEST_TMPDIR/$APP" &
  local app=$!
  "$SCRIPT" sh -c "echo ran > '$BATS_TEST_TMPDIR/ran'" &
  local run_pid=$!
  sleep 1.5
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
  run "$SCRIPT" --status
  kill "$app"; wait "$app" 2>/dev/null || true
  [[ "$output" == *"waiting: $APP is running (a real-time app)"* ]]
  wait "$run_pid"
  [ "$(cat "$BATS_TEST_TMPDIR/ran")" = ran ]
}

@test "heavy-run: realtime: a running run stops while a listed app runs, then goes on" {
  make_fake_app 6
  local out="$BATS_TEST_TMPDIR/out"
  "$SCRIPT" sh -c "for i in 1 2 3 4 5 6 7 8; do echo \$i >> '$out'; sleep 0.5; done" 2>"$BATS_TEST_TMPDIR/err" &
  local run_pid=$! i
  for i in $(seq 100); do [ -s "$out" ] && break; sleep 0.1; done  # the run has started
  "$BATS_TEST_TMPDIR/$APP" &
  local app=$!
  sleep 3.5  # the app check runs every 1 s and is cached for 2 s
  local a b
  a=$(wc -l < "$out"); sleep 0.8; b=$(wc -l < "$out")
  [ "$a" -eq "$b" ]
  wait "$app"
  wait "$run_pid"
  [ "$(wc -l < "$out")" -eq 8 ]
  grep -q "heavy-run: paused: $APP is running" "$BATS_TEST_TMPDIR/err"
  grep -q "heavy-run: resumed" "$BATS_TEST_TMPDIR/err"
}

@test "heavy-run: realtime: GeForce NOW is listed by default" {
  grep -q 'HEAVY_RUN_PAUSE_APPS="${HEAVY_RUN_PAUSE_APPS-GeForceNOW}"' "$SCRIPT"
}

@test "heavy-run: project: a run waits at its project cap while another project's run starts" {
  export HEAVY_RUN_SLOTS=10 HEAVY_RUN_PROJECT_SLOTS=2
  HEAVY_RUN_PROJECT=/p/alpha start_holder
  HEAVY_RUN_PROJECT=/p/alpha start_holder
  wait_held 2
  HEAVY_RUN_PROJECT=/p/alpha "$SCRIPT" touch "$BATS_TEST_TMPDIR/a3" &
  wait_queued 1
  HEAVY_RUN_PROJECT=/p/beta "$SCRIPT" touch "$BATS_TEST_TMPDIR/b1"
  [ -e "$BATS_TEST_TMPDIR/b1" ]
  [ ! -e "$BATS_TEST_TMPDIR/a3" ]
  run "$SCRIPT" --status
  [[ "$output" == *"(waiting: project cap: 2/2 runs of alpha)"* ]]
  release_all
  [ -e "$BATS_TEST_TMPDIR/a3" ]
}

@test "heavy-run: project: worktrees of one repo share its cap" {
  command -v git >/dev/null || skip "needs git"
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_PROJECT_SLOTS=1
  local repo="$BATS_TEST_TMPDIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m init
  git -C "$repo" worktree add -q "$BATS_TEST_TMPDIR/wt"
  cd "$repo"
  start_holder
  wait_held 1
  cd "$BATS_TEST_TMPDIR/wt"
  "$SCRIPT" touch "$BATS_TEST_TMPDIR/second" &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "$output" == *"(waiting: project cap: 1/1 runs of repo)"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/second" ]
  release_all
  [ -e "$BATS_TEST_TMPDIR/second" ]
}

@test "heavy-run: memory guard: under pressure a newer run stops while the oldest goes on" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_PROBE="test -e '$BATS_TEST_TMPDIR/pressure' && echo memory pressure warn"
  local old="$BATS_TEST_TMPDIR/old" new="$BATS_TEST_TMPDIR/new" i
  "$SCRIPT" sh -c "for i in \$(seq 40); do echo \$i >> '$old'; sleep 0.25; done" &
  for i in $(seq 50); do [ -s "$old" ] && break; sleep 0.1; done
  "$SCRIPT" sh -c "for i in \$(seq 12); do echo \$i >> '$new'; sleep 0.25; done" 2>"$BATS_TEST_TMPDIR/err" &
  local new_pid=$!
  for i in $(seq 50); do [ -s "$new" ] && break; sleep 0.1; done
  : >"$BATS_TEST_TMPDIR/pressure"
  sleep 2.5  # the guard asks at most every 2 s
  local n1 o1 n2 o2
  n1=$(wc -l < "$new"); o1=$(wc -l < "$old"); sleep 1; n2=$(wc -l < "$new"); o2=$(wc -l < "$old")
  [ "$n1" -eq "$n2" ]
  [ "$o2" -gt "$o1" ]
  rm "$BATS_TEST_TMPDIR/pressure"
  wait "$new_pid"
  [ "$(wc -l < "$new")" -eq 12 ]
  grep -q "heavy-run: paused: memory pressure warn (older runs go first)" "$BATS_TEST_TMPDIR/err"
  grep -q "heavy-run: resumed" "$BATS_TEST_TMPDIR/err"
  wait
}

@test "heavy-run: memory guard: HEAVY_RUN_MEMORY_GUARD=0 keeps a newer run going" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_MEMORY_GUARD=0 HEAVY_RUN_PROBE="test -e '$BATS_TEST_TMPDIR/pressure' && echo memory pressure warn"
  start_holder
  wait_held 1
  local new="$BATS_TEST_TMPDIR/new"
  "$SCRIPT" sh -c "for i in \$(seq 16); do echo \$i >> '$new'; sleep 0.25; done" &
  local new_pid=$! i
  for i in $(seq 50); do [ -s "$new" ] && break; sleep 0.1; done
  : >"$BATS_TEST_TMPDIR/pressure"
  sleep 2.5
  local n1 n2
  n1=$(wc -l < "$new"); sleep 0.8; n2=$(wc -l < "$new")
  [ "$n2" -gt "$n1" ]
  wait "$new_pid"
  release_all
}

@test "heavy-run: project: rejects a bad HEAVY_RUN_PROJECT_SLOTS or HEAVY_RUN_MEMORY_GUARD" {
  HEAVY_RUN_PROJECT_SLOTS=0 run "$SCRIPT" true
  [ "$status" -eq 2 ] && [[ "$output" == *"HEAVY_RUN_PROJECT_SLOTS must be 1-64"* ]]
  HEAVY_RUN_MEMORY_GUARD=yes run "$SCRIPT" true
  [ "$status" -eq 2 ] && [[ "$output" == *"HEAVY_RUN_MEMORY_GUARD must be 0 or 1"* ]]
}

@test "heavy-run: the state folder is private: folder 0700, files 0600" {
  mkdir -p "$HEAVY_RUN_DIR"
  chmod 755 "$HEAVY_RUN_DIR"
  "$SCRIPT" true
  mode() { perl -e 'printf "%o\n", (stat $ARGV[0])[2] & 07777' "$1"; }
  [ "$(mode "$HEAVY_RUN_DIR")" = 700 ]
  [ "$(mode "$HEAVY_RUN_DIR/lock")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/seq")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/slots/1")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/waits.log")" = 600 ]
}

#!/usr/bin/env bats
# Tests for bin/heavy-run — heavy commands in shared slots (one by default), at low priority.
# Most tests pin one slot (the old single-lock behavior); the slot tests set more.

SCRIPT="$BATS_TEST_DIRNAME/../bin/heavy-run"
load helpers/realtime-probe

bats_require_minimum_version 1.5.0

# Each test owns its queue and scratch home. The affected gate runs this
# file separately so its workers share one job budget.
setup_file() {
  unset BATS_NO_PARALLELIZE_WITHIN_FILE
}

setup() {
  export HEAVY_RUN_DIR="$BATS_TEST_TMPDIR/hr"
  # A scratch HOME keeps the real heavy_run_* settings out; a probe that
  # prints nothing means memory is fine, so tests do not depend on this Mac.
  export HOME="$BATS_TEST_TMPDIR/home" HEAVY_RUN_SLOTS=1 HEAVY_RUN_RAMP=0 HEAVY_RUN_PROBE=true
  # No real-time app holds the tests, even while one runs on this Mac.
  export HEAVY_RUN_PAUSE_APPS=""
  unset XDG_CONFIG_HOME HEAVY_RUN_MAX_LOAD HEAVY_RUN_EXCLUSIVE_WAIT
  unset HEAVY_RUN_HELD FIFO_RELEASE
  unset BATS_RT_PROBE_ROOT BATS_RT_PROBE_CHILDREN
}

teardown() {
  rt_probe_cleanup
  if [ -n "${INCOMPLETE_HOLDER:-}" ]; then
    [ -z "${FIFO_RELEASE:-}" ] || release_fifo_holder
    local child live
    for child in "$INCOMPLETE_HOLDER" "${INCOMPLETE_WAITER:-}" "${FAKE_PID:-}"; do
      [ -n "$child" ] || continue
      for live in $(jobs -p); do
        if [ "$live" = "$child" ]; then
          kill -CONT "$child" 2>/dev/null || true
          kill -TERM "$child" 2>/dev/null || true
        fi
      done
      wait "$child" 2>/dev/null || true
    done
    FIFO_RELEASE=""
  fi
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

# Wait up to 5 s until --status lists $1 live queue entries, each past its
# first start check: a new ticket reads "(waiting: starting)" until then.
# An optional reason must appear in a queue entry in the same snapshot.
wait_queued() {
  local i s
  for i in $(seq 50); do
    s=$("$SCRIPT" --status)
    if [ "$(grep -c '^queue ' <<<"$s")" -ge "$1" ] && ! grep -q '(waiting: starting)' <<<"$s"; then
      if [ -z "${2:-}" ] || grep '^queue ' <<<"$s" | grep -Fq "(waiting: $2)"; then
        return 0
      fi
    fi
    sleep 0.1
  done
  printf '%s\n' "$s" >&2
  return 1
}

# The 60-second alarm only bounds an abandoned fixture, not queue acceptance.
start_fifo_holder() {
  FIFO_RELEASE="$BATS_TEST_TMPDIR/release-holder"
  "$SCRIPT" perl -e '$SIG{ALRM} = "DEFAULT"; alarm 60; until (-e $ARGV[0]) { select undef, undef, undef, 0.1 }' "$FIFO_RELEASE" &
}

release_fifo_holder() {
  : > "$FIFO_RELEASE"
}

# Hold a live ticket (an flock on its file) without taking the lock; the pid
# is $FAKE_PID. $1 is the ticket number. Stop it with: kill "$FAKE_PID".
fake_live_ticket() {
  local mode="${2:-complete}" ready="$BATS_TEST_TMPDIR/fake-ticket-ready" i
  mkdir -p "$HEAVY_RUN_DIR/queue"
  perl -e 'use Fcntl ":flock"; use IO::Handle; open(F, ">>", "$ARGV[0]-$$") or die; flock(F, LOCK_EX) or die; print F "pid=$$ cwd=/x cmd=fake\n"; print F "wait=\nproject=fixture\nkind=v2\nexclusive=0\n" if $ARGV[1] eq "complete"; F->flush; close STDOUT; open(R, ">", $ARGV[2]) or die; close R; sleep 30' "$HEAVY_RUN_DIR/queue/$1" "$mode" "$ready" &
  FAKE_PID=$!
  for i in $(seq 50); do [ -e "$ready" ] && return 0; sleep 0.1; done
  return 1
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
  # The gate ticket stays while the first run holds it.
  [ -z "$(ls "$HEAVY_RUN_DIR/queue" | grep -v "^0000000000-0$")" ]
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

@test "heavy-run: interrupted file-output waiters retire before release" {
  local i pid rc live owned ticket
  local -a matches
  start_fifo_holder
  INCOMPLETE_HOLDER=$!
  wait_held
  for ((i=1; i<=20; i++)); do
    kill -0 "$INCOMPLETE_HOLDER"
    "$SCRIPT" touch "$BATS_TEST_TMPDIR/cancelled-$i" >"$BATS_TEST_TMPDIR/interrupted-$i.log" 2>&1 &
    pid=$!
    INCOMPLETE_WAITER="$pid"
    wait_queued 1
    matches=("$HEAVY_RUN_DIR/queue/"*-"$pid")
    [ "${#matches[@]}" -eq 1 ] && [ -f "${matches[0]}" ]
    ticket="${matches[0]}"
    owned=no
    for live in $(jobs -p); do [ "$live" != "$pid" ] || owned=yes; done
    [ "$owned" = yes ]
    kill -INT "$pid"
    rc=0; wait "$pid" || rc=$?
    INCOMPLETE_WAITER=""
    [ "$rc" -eq 130 ]
    [ ! -e "$ticket" ] && [ ! -e "$ticket.why" ] && [ ! -e "$ticket.grant" ]
  done
  kill -0 "$INCOMPLETE_HOLDER"
  release_fifo_holder
  wait "$INCOMPLETE_HOLDER"
  INCOMPLETE_HOLDER="" FIFO_RELEASE=""
  "$SCRIPT" touch "$BATS_TEST_TMPDIR/sentinel"
  [ -e "$BATS_TEST_TMPDIR/sentinel" ]
  sleep 1
  for ((i=1; i<=20; i++)); do [ ! -e "$BATS_TEST_TMPDIR/cancelled-$i" ]; done
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
  start_fifo_holder
  holder=$!
  wait_held
  "$SCRIPT" echo victim &
  victim=$!
  wait_queued 1
  sleep "${BATS_HEAVY_RUN_WAITER_DELAY:-0}"
  kill -KILL "$victim"
  rc=0; wait "$victim" 2>/dev/null || rc=$?
  [ "$rc" -eq 137 ]
  release_fifo_holder
  wait "$holder"
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

@test "heavy-run: an incomplete live identity holds new admissions" {
  start_fifo_holder
  holder=$!
  INCOMPLETE_HOLDER="$holder"
  wait_held
  marker="$BATS_TEST_TMPDIR/ran"
  "$SCRIPT" touch "$marker" &
  waiter=$!
  INCOMPLETE_WAITER="$waiter"
  wait_queued 1
  local ticket="" candidate number later why i
  for candidate in "$HEAVY_RUN_DIR/queue/"*-"$waiter"; do
    [ -f "$candidate" ] || continue
    ticket="$candidate"
    break
  done
  [ -n "$ticket" ]
  number="${ticket##*/}"
  number="${number%%-*}"
  printf -v later '%010d' "$((10#$number + 1))"
  fake_live_ticket "$later" incomplete
  release_fifo_holder
  wait "$holder"
  why="$ticket.why"
  for i in $(seq 50); do grep -q '^queue project metadata unavailable$' "$why" 2>/dev/null && break; sleep 0.1; done
  [ -f "$why" ]
  grep -q '^queue project metadata unavailable$' "$why"
  [ ! -e "$marker" ]
  kill "$FAKE_PID"
  wait "$FAKE_PID" 2>/dev/null || true
  FAKE_PID=""
  wait "$waiter"
  [ -e "$marker" ]
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
  "$SCRIPT" "$@" perl -e '$SIG{ALRM} = "DEFAULT"; alarm 60; until (-e $ARGV[0]) { select undef, undef, undef, 0.05 }' "$RELEASE_ALL" &
}

release_all() {
  : > "$RELEASE_ALL"
  wait
}

@test "heavy-run: bare status reads an idle queue without creating state" {
  run env HEAVY_RUN_NICE=invalid "$SCRIPT" status
  [ "$status" -eq 0 ]
  [ "$output" = "free: 0/1 slots busy" ]
  [ ! -e "$HEAVY_RUN_DIR" ]
}

@test "heavy-run: bare status reads a busy queue without a ticket" {
  start_holder
  if ! wait_held 1; then
    release_all
    return 1
  fi
  local before after
  before=$(find "$HEAVY_RUN_DIR/queue" -type f -print | sort)
  run env HEAVY_RUN_NICE=invalid "$SCRIPT" status
  after=$(find "$HEAVY_RUN_DIR/queue" -type f -print | sort)
  release_all
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "busy: 1/1 slots" ]
  [ "$before" = "$after" ]
}

@test "heavy-run: bare status alias still allows a status program with an argument" {
  local mock_bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$mock_bin"
  printf '%s\n' '#!/bin/sh' 'printf "%s\n" "$1"' > "$mock_bin/status"
  chmod 700 "$mock_bin/status"
  run env PATH="$mock_bin:$PATH" "$SCRIPT" status fixture-argument
  [ "$status" -eq 0 ]
  [ "$output" = fixture-argument ]
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

@test "heavy-run: exclusive deadline retires only the waiting run" {
  export HEAVY_RUN_SLOTS=2 HEAVY_RUN_FREE_PROBE='echo 99'
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_exclusive_wait_seconds: 12\n' > "$HOME/.config/chezmoi/chezmoi.yaml"
  start_holder
  wait_held 1
  run "$SCRIPT" --status
  [[ "${lines[1]}" =~ ^slot.*\(running:\ [0-9]+s\)$ ]]

  local waiter next retry=0 next_status=0
  marker="$BATS_TEST_TMPDIR/exclusive-started"
  timeout 15 env HEAVY_RUN_EXCLUSIVE_WAIT=5 "$SCRIPT" --exclusive touch "$marker" > "$BATS_TEST_TMPDIR/expired" 2>&1 &
  waiter=$!
  wait_queued 1
  timeout 15 "$SCRIPT" touch "$BATS_TEST_TMPDIR/next-started" &
  next=$!
  wait "$waiter" || retry=$?
  wait "$next" || next_status=$?
  run "$SCRIPT" --status
  release_all

  [ "$retry" -eq 75 ]
  [ "$next_status" -eq 0 ]
  grep -q 'exclusive wait reached 5s' "$BATS_TEST_TMPDIR/expired"
  [ ! -e "$marker" ]
  [ -e "$BATS_TEST_TMPDIR/next-started" ]
  [ "${lines[0]}" = "busy: 1/2 slots" ]
  [[ "$output" != *'queue '* ]]
}

@test "heavy-run: exclusive deadline applies while the ticket sequence is locked" {
  mkdir -p "$HEAVY_RUN_DIR"
  local holder
  perl -MFcntl=:flock -e '
    $SIG{ALRM} = "DEFAULT";
    alarm 15;
    open(my $seq, ">", $ARGV[0]) or die $!;
    flock($seq, LOCK_EX) or die $!;
    open(my $ready, ">", $ARGV[1]) or die $!;
    close $ready;
    until (-e $ARGV[2]) { select undef, undef, undef, 0.05 }
  ' "$HEAVY_RUN_DIR/seq" "$BATS_TEST_TMPDIR/ready" "$BATS_TEST_TMPDIR/release-seq" &
  holder=$!
  for i in $(seq 50); do [ -e "$BATS_TEST_TMPDIR/ready" ] && break; sleep 0.1; done
  [ -e "$BATS_TEST_TMPDIR/ready" ]

  run timeout 8 env HEAVY_RUN_EXCLUSIVE_WAIT=2 "$SCRIPT" --exclusive touch "$BATS_TEST_TMPDIR/exclusive-started"
  : > "$BATS_TEST_TMPDIR/release-seq"
  wait "$holder"
  [ "$status" -eq 75 ]
  [[ "$output" == *'exclusive wait reached 2s'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/exclusive-started" ]
}

@test "heavy-run: slots: a SIGKILLed run frees its slot at once" {
  export HEAVY_RUN_SLOTS=1
  "$SCRIPT" sleep 30 &
  victim=$!
  wait_held 1
  child=$(sed -n 's/.* pid=\([0-9]*\) .*/\1/p' "$HEAVY_RUN_DIR/slots/s1.owner")
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

@test "heavy-run: slots: low free memory holds extra runs but never the first" {
  echo 10 >"$BATS_TEST_TMPDIR/free"
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_FREE_PROBE="cat '$BATS_TEST_TMPDIR/free'"
  start_holder
  wait_held 1
  marker="$BATS_TEST_TMPDIR/second"
  "$SCRIPT" touch "$marker" &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "${lines[2]}" == "queue 1: "*"(waiting: free memory 10% below 25%)" ]]
  [ ! -e "$marker" ]
  echo 60 >"$BATS_TEST_TMPDIR/free"
  for i in $(seq 50); do [ -e "$marker" ] && break; sleep 0.1; done
  [ -e "$marker" ]
  release_all
}

@test "heavy-run: slots: HEAVY_RUN_MIN_FREE_PCT=0 turns the free memory check off" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_MIN_FREE_PCT=0 HEAVY_RUN_FREE_PROBE="echo 1"
  start_holder
  wait_held 1
  run "$SCRIPT" echo ran
  [ "$output" = "ran" ]
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
  [[ "${lines[2]}" == *"(waiting: load "*" above 0.0001)" ]] || [ "${#lines[@]}" -le 3 ]
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

@test "heavy-run: realtime probe: first normal holds status two" { rt_probe_unknown normal error2; }
@test "heavy-run: realtime probe: exclusive holds status two" { rt_probe_unknown exclusive error2; }
@test "heavy-run: realtime probe: additional holds status two" { rt_probe_unknown additional error2; }
@test "heavy-run: realtime probe: first normal holds status three" { rt_probe_unknown normal error3; }
@test "heavy-run: realtime probe: exclusive holds status three" { rt_probe_unknown exclusive error3; }
@test "heavy-run: realtime probe: additional holds status three" { rt_probe_unknown additional error3; }
@test "heavy-run: realtime probe: first normal holds an unavailable lookup" { rt_probe_unknown normal missing; }
@test "heavy-run: realtime probe: exclusive holds an unavailable lookup" { rt_probe_unknown exclusive missing; }
@test "heavy-run: realtime probe: additional holds an unavailable lookup" { rt_probe_unknown additional missing; }
@test "heavy-run: realtime probe: first normal holds empty successful output" { rt_probe_unknown normal empty; }
@test "heavy-run: realtime probe: exclusive holds empty successful output" { rt_probe_unknown exclusive empty; }
@test "heavy-run: realtime probe: additional holds empty successful output" { rt_probe_unknown additional empty; }
@test "heavy-run: realtime probe: malformed match remains unknown" { rt_probe_unknown normal malformed; }
@test "heavy-run: realtime probe: contradictory no-match remains unknown" { rt_probe_unknown normal contradictory; }
@test "heavy-run: realtime probe: blank no-match output remains unknown" { rt_probe_unknown normal blank_no_match; }
@test "heavy-run: realtime probe: an extra match output line remains unknown" { rt_probe_unknown normal extra_line; }
@test "heavy-run: realtime probe: verified no-match admits first normal" { rt_probe_clear normal; }
@test "heavy-run: realtime probe: verified no-match admits exclusive" { rt_probe_clear exclusive; }
@test "heavy-run: realtime probe: verified no-match admits additional" { rt_probe_clear additional; }
@test "heavy-run: realtime probe: verified match holds first normal" { rt_probe_present normal; }
@test "heavy-run: realtime probe: verified match holds exclusive" { rt_probe_present exclusive; }

@test "heavy-run: realtime probe: an empty app list does not query the probe" {
  rt_probe_setup
  rt_probe_mode error3
  export HEAVY_RUN_PAUSE_APPS=""
  rt_probe_spawn normal
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/admitted"
  wait "$BATS_RT_PROBE_PID"
  [ ! -e "$BATS_RT_PROBE_ROOT/seen/error3" ]
}

@test "heavy-run: realtime probe: unknown retains an existing pause until verified clear" {
  rt_probe_setup
  "$SCRIPT" perl -e '$SIG{ALRM}="DEFAULT"; alarm 35; open(my $p,">",$ARGV[0]) or die; print $p $$; close $p; until(-e $ARGV[1]) { select undef,undef,undef,0.05 } open(my $f,">",$ARGV[2]) or die; print $f "continued";' "$BATS_RT_PROBE_ROOT/workload-pid" "$BATS_RT_PROBE_ROOT/release-workload" "$BATS_RT_PROBE_ROOT/continued" > "$BATS_RT_PROBE_ROOT/controller.log" 2>&1 &
  BATS_RT_PROBE_PID=$!
  BATS_RT_PROBE_CHILDREN="$BATS_RT_PROBE_PID"
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/workload-pid"
  local workload i state mark="$HEAVY_RUN_DIR/slots/s1.paused"
  workload=$(cat "$BATS_RT_PROBE_ROOT/workload-pid")
  rt_probe_mode present
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/present"
  for i in $(seq 100); do
    state=$(ps -o state= -p "$workload")
    case "$state" in *T*) break ;; esac
    sleep 0.1
  done
  [[ "$state" == *T* ]]
  [ -e "$mark" ]
  rt_probe_mode error3
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/seen/error3"
  : > "$BATS_RT_PROBE_ROOT/release-workload"
  local observed=false
  for i in $(seq 100); do
    if [ -e "$BATS_RT_PROBE_ROOT/continued" ]; then observed=true; break; fi
    if [ -f "$mark" ] && [ "$(cat "$mark")" = 'real-time app probe unavailable' ]; then
      state=$(ps -o state= -p "$workload")
      case "$state" in *T*) observed=true; break ;; esac
    fi
    sleep 0.1
  done
  $observed
  [ ! -e "$BATS_RT_PROBE_ROOT/continued" ]
  [ "$(cat "$mark")" = 'real-time app probe unavailable' ]
  rt_probe_mode clear
  rt_probe_wait_path "$BATS_RT_PROBE_ROOT/continued"
  wait "$BATS_RT_PROBE_PID"
}

queue_directory_creation_fixture() {
  local fixture="$BATS_TEST_TMPDIR/queue-directory-creation"
  mkdir -p "$fixture"
  cat > "$fixture/HeavyQueueDirectoryFixture.pm" <<'PERL'
package HeavyQueueDirectoryFixture;
use Errno qw(EACCES EEXIST);

BEGIN {
  *CORE::GLOBAL::mkdir = sub {
    my ($path, $mode) = @_;
    $mode //= 0777;
    return CORE::mkdir($path, $mode) unless $path eq $ENV{FIXTURE_DIRECTORY};
    my $case = $ENV{FIXTURE_DIRECTORY_CASE};
    if ($case eq "directory") {
      CORE::mkdir($path, $mode) or die "fixture mkdir failed: $!\n";
    } elsif ($case eq "file") {
      open(my $file, ">", $path) or die "fixture file creation failed: $!\n";
      close($file) or die "fixture file close failed: $!\n";
    }
    open(my $receipt, ">", $ENV{FIXTURE_DIRECTORY_RECEIPT}) or die "fixture receipt failed: $!\n";
    print $receipt "$case\n";
    close($receipt) or die "fixture receipt close failed: $!\n";
    $! = $case eq "denied" ? EACCES : EEXIST;
    return 0;
  };
}
1;
PERL
  export PERL5LIB="$fixture" PERL5OPT=-MHeavyQueueDirectoryFixture LC_ALL=C
  export FIXTURE_DIRECTORY="$HEAVY_RUN_DIR/$1" FIXTURE_DIRECTORY_CASE="$2"
  export FIXTURE_DIRECTORY_RECEIPT="$fixture/injected"
}

assert_adopts_concurrent_queue_directory() {
  queue_directory_creation_fixture "$1" directory
  run --separate-stderr "$SCRIPT" sh -c 'printf "%s\n" "$HEAVY_RUN_HELD"'
  [ "$(cat "$FIXTURE_DIRECTORY_RECEIPT")" = directory ]
  [ -d "$FIXTURE_DIRECTORY" ]
  if [ "$status" -ne 0 ] || [ -n "$stderr" ]; then
    printf 'Expected a normal slot without diagnostics. Exit: %s\n%s\n' "$status" "$stderr" >&2
    return 1
  fi
  [ "$output" = "$HEAVY_RUN_DIR/slots/s1" ]
  [ "$(cat "$HEAVY_RUN_DIR/seq")" = 1 ]
}

@test "heavy-run: adopts an arrival directory another starter creates" {
  assert_adopts_concurrent_queue_directory queue
}

@test "heavy-run: adopts a slots directory another starter creates" {
  assert_adopts_concurrent_queue_directory slots
}

@test "heavy-run: refuses to use a non-directory slots path" {
  queue_directory_creation_fixture slots file
  run --separate-stderr "$SCRIPT" sh -c ': > "$1"' fixture "$BATS_TEST_TMPDIR/launched"
  [ "$(cat "$FIXTURE_DIRECTORY_RECEIPT")" = file ]
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"cannot create"* && "$stderr" == *"File exists"* ]]
  [ -f "$FIXTURE_DIRECTORY" ]
  [ ! -e "$BATS_TEST_TMPDIR/launched" ]
}

@test "heavy-run: a slots directory permission failure stays fatal" {
  queue_directory_creation_fixture slots denied
  run --separate-stderr "$SCRIPT" sh -c ': > "$1"' fixture "$BATS_TEST_TMPDIR/launched"
  [ "$(cat "$FIXTURE_DIRECTORY_RECEIPT")" = denied ]
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"cannot create"* && "$stderr" == *"Permission denied"* ]]
  [ ! -e "$FIXTURE_DIRECTORY" ]
  [ ! -e "$BATS_TEST_TMPDIR/launched" ]
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
  wait_queued 1 "project cap: 2/2 runs of alpha"
  [ ! -e "$BATS_TEST_TMPDIR/a3" ]
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
  wait_queued 1 "project cap: 1/1 runs of repo"
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

@test "heavy-run: --no-pause: under pressure a newer no-pause run goes on beside the oldest" {
  export HEAVY_RUN_SLOTS=4 HEAVY_RUN_PROBE="test -e '$BATS_TEST_TMPDIR/pressure' && echo memory pressure warn"
  start_holder
  wait_held 1
  local new="$BATS_TEST_TMPDIR/new"
  "$SCRIPT" --no-pause sh -c "for i in \$(seq 16); do echo \$i >> '$new'; sleep 0.25; done" 2>"$BATS_TEST_TMPDIR/err" &
  local new_pid=$! i
  for i in $(seq 50); do [ -s "$new" ] && break; sleep 0.1; done
  : >"$BATS_TEST_TMPDIR/pressure"
  sleep 2.5
  local n1 n2
  n1=$(wc -l < "$new"); sleep 0.8; n2=$(wc -l < "$new")
  [ "$n2" -gt "$n1" ]
  wait "$new_pid"
  ! grep -q "heavy-run: paused" "$BATS_TEST_TMPDIR/err"
  release_all
}

@test "heavy-run: heavy_run_exclusive_shared=1: an exclusive run starts beside a running run" {
  export HEAVY_RUN_SLOTS=2 HEAVY_RUN_RAMP=0 HEAVY_RUN_EXCLUSIVE_SHARED=1
  start_holder
  wait_held 1
  run timeout 20 "$SCRIPT" --exclusive sh -c 'echo "slot=$HEAVY_RUN_SLOT"'
  [ "$status" -eq 0 ]
  [ "$output" = "slot=2" ]
  release_all
}

@test "heavy-run: --no-pause: runs in a shared slot and hides its internal flag" {
  run "$SCRIPT" --no-pause sh -c 'echo "slot=$HEAVY_RUN_SLOT flag=${HEAVY_RUN_NOPAUSE_RUN-unset}"'
  [ "$status" -eq 0 ]
  [ "$output" = "slot=1 flag=unset" ]
  run "$SCRIPT" --no-pause
  [ "$status" -eq 2 ]
}

@test "heavy-run: project: rejects a bad HEAVY_RUN_PROJECT_SLOTS or HEAVY_RUN_MEMORY_GUARD" {
  HEAVY_RUN_PROJECT_SLOTS=0 run "$SCRIPT" true
  [ "$status" -eq 2 ] && [[ "$output" == *"HEAVY_RUN_PROJECT_SLOTS must be 1-64"* ]]
  HEAVY_RUN_MEMORY_GUARD=yes run "$SCRIPT" true
  [ "$status" -eq 2 ] && [[ "$output" == *"HEAVY_RUN_MEMORY_GUARD must be 0 or 1"* ]]
}

caller_mask_file() {
  local mask="$1" file="$2" mode="$3"
  shift 3
  run sh -c 'umask "$1"; shift; exec "$@"' sh "$mask" "$SCRIPT" "$@" sh -c ': > "$1"' sh "$file"
  [ "$status" -eq 0 ]
  [ "$(perl -e 'printf "%o\n", (stat $ARGV[0])[2] & 07777' "$file")" = "$mode" ]
}

@test "heavy-run: normal command keeps the caller mask" {
  caller_mask_file 022 "$BATS_TEST_TMPDIR/normal" 644
}

@test "heavy-run: exclusive command keeps the caller mask" {
  caller_mask_file 027 "$BATS_TEST_TMPDIR/exclusive" 640 --exclusive
}

@test "heavy-run: nested command keeps its immediate caller mask" {
  local file="$BATS_TEST_TMPDIR/nested"
  local nested='umask 027; exec "$1" sh -c "$2" sh "$3"'
  run sh -c 'umask 022; exec "$@"' sh "$SCRIPT" sh -c "$nested" sh "$SCRIPT" ': > "$1"' "$file"
  [ "$status" -eq 0 ]
  [ "$(perl -e 'printf "%o\n", (stat $ARGV[0])[2] & 07777' "$file")" = 640 ]
}

@test "heavy-run: a restrictive caller mask stays restrictive" {
  caller_mask_file 077 "$BATS_TEST_TMPDIR/private" 600
}

@test "heavy-run: the state folder is private: folder 0700, files 0600" {
  mkdir -p "$HEAVY_RUN_DIR"
  chmod 755 "$HEAVY_RUN_DIR"
  "$SCRIPT" true
  mode() { perl -e 'printf "%o\n", (stat $ARGV[0])[2] & 07777' "$1"; }
  [ "$(mode "$HEAVY_RUN_DIR")" = 700 ]
  [ "$(mode "$HEAVY_RUN_DIR/lock")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/seq")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/slots/s1")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/sched.lock")" = 600 ]
  [ "$(mode "$HEAVY_RUN_DIR/waits.log")" = 600 ]
}

# --- The scheduler: one process decides for the whole queue ---

@test "heavy-run: scheduler: a waiter's ticket gets its reason from the scheduler" {
  start_holder
  wait_held 1
  "$SCRIPT" true &
  wait_queued 1
  ls "$HEAVY_RUN_DIR/queue" | grep -q '\.why$'
  [ "$(cat "$HEAVY_RUN_DIR"/queue/*.why)" = "no free slot (1/1 busy)" ]
  release_all
  [ -z "$(ls "$HEAVY_RUN_DIR/queue" | grep -v '^0000000000-0$')" ]
}

@test "heavy-run: scheduler: a lowered heavy_run_slots holds runs already waiting" {
  unset HEAVY_RUN_SLOTS
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_slots: 1\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  start_holder
  wait_held 1
  marker="$BATS_TEST_TMPDIR/second"
  printf 'data:\n  heavy_run_slots: 3\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  "$SCRIPT" touch "$marker" &
  for i in $(seq 50); do [ -e "$marker" ] && break; sleep 0.1; done
  [ -e "$marker" ]
  printf 'data:\n  heavy_run_slots: 1\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  sleep 1.2
  "$SCRIPT" touch "$marker.3" &
  wait_queued 1
  run "$SCRIPT" --status
  [[ "$output" == *"(waiting: no free slot (1/1 busy))"* ]]
  release_all
  [ -e "$marker.3" ]
}

@test "heavy-run: scheduler: an older heavy-run waiter keeps its place in line" {
  OLD="$BATS_TEST_DIRNAME/fixtures/heavy-run-429"
  log="$BATS_TEST_TMPDIR/order"
  start_holder
  wait_held 1
  # The older code can not see the new slot; only the gate keeps it waiting.
  "$OLD" sh -c "echo old >>'$log'" &
  wait_queued 1
  sleep 1
  [ ! -e "$log" ]
  "$SCRIPT" sh -c "echo new >>'$log'" &
  wait_queued 2
  run "$SCRIPT" --status
  [[ "${lines[2]}" == "queue 1: "*"echo old"*"(waiting: no free slot (1/1 busy))" ]]
  [[ "${lines[3]}" == "queue 2: "*"echo new"*"(waiting: behind queue 1)" ]]
  release_all
  run cat "$log"
  [ "${lines[0]}" = old ]
  [ "${lines[1]}" = new ]
  [ ! -e "$HEAVY_RUN_DIR/gate-open" ]
}

@test "heavy-run: scheduler counts a gated legacy slot taken during a pass" {
  run --separate-stderr perl "$BATS_TEST_DIRNAME/helpers/heavy-run-legacy-handoff.pl" \
    "$SCRIPT" "$HEAVY_RUN_DIR" "$BATS_TEST_TMPDIR/handoff"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$stderr" >&2
    return 1
  fi
  [ "$output" = "Observed the legacy slot before grant; younger command ran once after release." ]
}

check_legacy_exclusive_reservation() {
  HEAVY_RUN_SLOTS=2 HEAVY_RUN_EXCLUSIVE_SHARED=0 run --separate-stderr \
    perl "$BATS_TEST_DIRNAME/helpers/heavy-run-legacy-handoff.pl" \
    "$SCRIPT" "$HEAVY_RUN_DIR" "$BATS_TEST_TMPDIR/handoff" "$1"
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$stderr" >&2
    return 1
  fi
  [ "$output" = "Observed the exclusive reservation; younger command ran once after release." ]
}

@test "heavy-run: selecting an older exclusive waiter reserves later grants" {
  check_legacy_exclusive_reservation exclusive-select
}

@test "heavy-run: an open gate keeps the older exclusive reservation" {
  check_legacy_exclusive_reservation exclusive-open
}

# Start a waiter from a shell that exits at once, so the waiter is orphaned.
# The shell lives 0.5 s, so the waiter starts with it as parent (a waiter
# that starts under pid 1 is exempt). $1 is the output redirect; the rest is env.
start_orphan() {
  local redirect=$1; shift
  env "$@" sh -c "'$SCRIPT' touch '$BATS_TEST_TMPDIR/ran' $redirect & echo \$! > '$BATS_TEST_TMPDIR/pid'; sleep 0.5"
}

@test "heavy-run: orphans: a waiter whose caller died leaves the queue" {
  start_fifo_holder
  wait_held
  start_orphan '>/dev/null 2>&1'
  local pid i
  pid=$(cat "$BATS_TEST_TMPDIR/pid")
  for i in $(seq 50); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  ! kill -0 "$pid" 2>/dev/null || false
  [ "$("$SCRIPT" --status | grep -c '^queue ')" -eq 0 ]
  release_fifo_holder
  wait
  [ ! -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "heavy-run: orphans: a waiter that writes to a file keeps its place and runs" {
  start_fifo_holder
  wait_held
  start_orphan ">'$BATS_TEST_TMPDIR/log' 2>&1"
  wait_queued 1
  sleep 0.6
  [ "$("$SCRIPT" --status | grep -c '^queue ')" -eq 1 ]
  release_fifo_holder
  local i
  for i in $(seq 50); do [ -e "$BATS_TEST_TMPDIR/ran" ] && break; sleep 0.1; done
  [ -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "heavy-run: orphans: HEAVY_RUN_KEEP_ORPHAN=1 or nohup keeps the waiter" {
  start_fifo_holder
  wait_held
  start_orphan '>/dev/null 2>&1' HEAVY_RUN_KEEP_ORPHAN=1
  wait_queued 1
  sleep 0.6
  [ "$("$SCRIPT" --status | grep -c '^queue ')" -eq 1 ]
  sh -c "nohup '$SCRIPT' true >/dev/null 2>&1 & sleep 0.5"
  wait_queued 2
  sleep 0.6
  [ "$("$SCRIPT" --status | grep -c '^queue ')" -eq 2 ]
  release_fifo_holder
  local i
  for i in $(seq 50); do [ -e "$BATS_TEST_TMPDIR/ran" ] && break; sleep 0.1; done
  [ -e "$BATS_TEST_TMPDIR/ran" ]
}

@test "heavy-run: orphans: rejects a bad HEAVY_RUN_KEEP_ORPHAN" {
  run env HEAVY_RUN_KEEP_ORPHAN=yes "$SCRIPT" true
  [ "$status" -eq 2 ]
  [[ "$output" == *"HEAVY_RUN_KEEP_ORPHAN must be 0 or 1"* ]]
}

# --- Auto load cap (heavy_run_max_load: auto).
auto_env() {
  export HEAVY_RUN_SLOTS=2 HEAVY_RUN_MAX_LOAD=auto HEAVY_RUN_CORES=10
  printf '%s\n' "${1:-95}" >"$BATS_TEST_TMPDIR/load"
  export HEAVY_RUN_LOAD_PROBE="cat $BATS_TEST_TMPDIR/load"
}

@test "heavy-run: auto load cap starts at 8 x cores and --status says why" {
  auto_env 3
  run "$SCRIPT" --status
  [ "${lines[1]}" = "load cap: 80 auto, load now 3 (start: 8 x 10 cores)" ]
}

@test "heavy-run: auto load cap reads 'auto' from the setting" {
  unset HEAVY_RUN_MAX_LOAD
  auto_env 3
  unset HEAVY_RUN_MAX_LOAD
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  heavy_run_max_load: auto  # tuned\n' >"$HOME/.config/chezmoi/chezmoi.yaml"
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 80 auto"* ]]
}

@test "heavy-run: auto load cap drops 20% after a failed run at high load" {
  auto_env 95
  run "$SCRIPT" false
  [ "$status" -eq 1 ]
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 64 auto"*"lowered from 80: a "*" run failed (exit 1) at load 95)" ]]
  # One overload counts once: a second failure within a minute keeps 64.
  run "$SCRIPT" false
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 64 auto"* ]]
}

@test "heavy-run: auto load cap keeps its value after a failure at low load" {
  auto_env 5
  run "$SCRIPT" false
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 80 auto"* ]]
}

@test "heavy-run: auto load cap rises 5% when a run passes while runs waited on load" {
  auto_env 95
  mkdir -p "$HEAVY_RUN_DIR"
  printf '64\told\n' >"$HEAVY_RUN_DIR/load-cap"
  touch -t 202601010000 "$HEAVY_RUN_DIR/load-cap"
  touch "$HEAVY_RUN_DIR/load-waited"
  run "$SCRIPT" true
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 67 auto"*"raised from 64"* ]]
}

@test "heavy-run: auto load cap stays within 2-16 x cores" {
  auto_env 3
  mkdir -p "$HEAVY_RUN_DIR"
  printf '1\tx\n' >"$HEAVY_RUN_DIR/load-cap"
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 20 auto"*"floor 2 x 10 cores)" ]]
  printf '9999\tx\n' >"$HEAVY_RUN_DIR/load-cap"
  run "$SCRIPT" --status
  [[ "${lines[1]}" == "load cap: 160 auto"*"ceiling 16 x 10 cores)" ]]
}

@test "heavy-run: monitor logs each run's exit and load, and a sample line" {
  auto_env 42
  run "$SCRIPT" sh -c 'exit 3'
  [ "$status" -eq 3 ]
  [ "$(head -1 "$HEAVY_RUN_DIR/runs.tsv")" = "$(printf 'time\texit\tseconds\tload_start\tload_peak\tbusy_start\tcap\tproject')" ]
  [ "$(tail -1 "$HEAVY_RUN_DIR/runs.tsv" | cut -f2,4,5,7)" = "$(printf '3\t42\t42\t80')" ]
  [ "$(tail -1 "$HEAVY_RUN_DIR/monitor.tsv" | cut -f2,6)" = "$(printf '42\t80')" ]
  [ "$(stat -f %Lp "$HEAVY_RUN_DIR/runs.tsv" 2>/dev/null || stat -c %a "$HEAVY_RUN_DIR/runs.tsv")" = 600 ]
}

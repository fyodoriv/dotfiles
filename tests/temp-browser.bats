#!/usr/bin/env bats
# temp-browser: one locked, disposable browser for agents.
# TEMP_BROWSER_CHROME points at a stub, so no real browser starts.

SCRIPT="$BATS_TEST_DIRNAME/../bin/temp-browser"

setup() {
  TEST_DIR="$(mktemp -d)"
  export TEMP_BROWSER_STATE_DIR="$TEST_DIR/state"
  export TEMP_BROWSER_READY_TIMEOUT=0
  export TEMP_BROWSER_PORT=9399
  cat > "$TEST_DIR/fake-chrome" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${TEMP_BROWSER_STATE_DIR}/launch-args"
exec sleep 300
STUB
  chmod +x "$TEST_DIR/fake-chrome"
  export TEMP_BROWSER_CHROME="$TEST_DIR/fake-chrome"
}

teardown() {
  local pid
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid" 2>/dev/null || true)"
  [ -z "$pid" ] || kill "$pid" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

@test "acquire prints the CDP port and records the lock" {
  run "$SCRIPT" acquire --owner agent-a --reason "bot sign-in"
  [ "$status" -eq 0 ]
  [ "$output" = "9399" ]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/owner")" = "agent-a" ]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/reason")" = "bot sign-in" ]
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  kill -0 "$pid"
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/expires")" -gt "$(date +%s)" ]
}

@test "acquire launches headless with a fresh profile and the port" {
  "$SCRIPT" acquire --owner a --reason r >/dev/null
  profile="$(cat "$TEMP_BROWSER_STATE_DIR/lock/profile")"
  [ -d "$profile" ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$TEMP_BROWSER_STATE_DIR/launch-args" ] && break; sleep 0.1; done
  grep -qx -- '--headless=new' "$TEMP_BROWSER_STATE_DIR/launch-args"
  grep -qx -- '--remote-debugging-port=9399' "$TEMP_BROWSER_STATE_DIR/launch-args"
  grep -qx -- "--user-data-dir=$profile" "$TEMP_BROWSER_STATE_DIR/launch-args"
}

@test "second acquirer is refused with holder name and reason" {
  "$SCRIPT" acquire --owner agent-a --reason "bot sign-in" >/dev/null
  run "$SCRIPT" acquire --owner agent-b --reason other
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent-a"* ]]
  [[ "$output" == *"bot sign-in"* ]]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/owner")" = "agent-a" ]
}

@test "acquire requires owner and reason" {
  run "$SCRIPT" acquire --owner a
  [ "$status" -eq 2 ]
  run "$SCRIPT" acquire --reason r
  [ "$status" -eq 2 ]
}

@test "dead browser pid is discarded and taken over" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  old_profile="$(cat "$TEMP_BROWSER_STATE_DIR/lock/profile")"
  kill "$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  sleep 0.2
  run "$SCRIPT" acquire --owner agent-b --reason r2
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/owner")" = "agent-b" ]
  [ ! -e "$old_profile" ]
}

@test "expired lease is discarded, its browser stopped, and taken over" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  old_pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  echo 1 > "$TEMP_BROWSER_STATE_DIR/lock/expires"
  run "$SCRIPT" acquire --owner agent-b --reason r2
  [ "$status" -eq 0 ]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/owner")" = "agent-b" ]
  sleep 0.2
  ! kill -0 "$old_pid" 2>/dev/null
}

@test "status shows holder, reason, pid, and lease expiry" {
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"free"* ]]
  "$SCRIPT" acquire --owner agent-a --reason "bot sign-in" >/dev/null
  run "$SCRIPT" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"owner: agent-a"* ]]
  [[ "$output" == *"reason: bot sign-in"* ]]
  [[ "$output" == *"pid: $(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"* ]]
  [[ "$output" == *"lease expires:"* ]]
  [[ "$output" == *"port: 9399"* ]]
}

@test "release stops the browser, deletes the profile, frees the lock" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  profile="$(cat "$TEMP_BROWSER_STATE_DIR/lock/profile")"
  run "$SCRIPT" release --owner agent-a
  [ "$status" -eq 0 ]
  sleep 0.2
  ! kill -0 "$pid" 2>/dev/null
  [ ! -e "$profile" ]
  [ ! -e "$TEMP_BROWSER_STATE_DIR/lock" ]
  run "$SCRIPT" acquire --owner agent-b --reason r
  [ "$status" -eq 0 ]
}

@test "release by another owner is refused" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  run "$SCRIPT" release --owner agent-b
  [ "$status" -ne 0 ]
  [[ "$output" == *"agent-a"* ]]
  [ -d "$TEMP_BROWSER_STATE_DIR/lock" ]
}

@test "release when free succeeds" {
  run "$SCRIPT" release --owner agent-a
  [ "$status" -eq 0 ]
}

@test "same owner re-acquire keeps the browser and prints the port" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  run "$SCRIPT" acquire --owner agent-a --reason r
  [ "$status" -eq 0 ]
  [ "$output" = "9399" ]
  [ "$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")" = "$pid" ]
}

@test "failed launch frees the lock" {
  export TEMP_BROWSER_CHROME="$TEST_DIR/missing-chrome"
  run "$SCRIPT" acquire --owner agent-a --reason r
  [ "$status" -ne 0 ]
  [ ! -e "$TEMP_BROWSER_STATE_DIR/lock" ]
}

@test "temp-browser never raises windows" {
  ! grep -qE 'osascript|activate|open -a' "$SCRIPT"
}

@test "busy exit code is 3 (documented contract)" {
  "$SCRIPT" acquire --owner agent-a --reason r >/dev/null
  run "$SCRIPT" acquire --owner agent-b --reason r2
  [ "$status" -eq 3 ]
  run "$SCRIPT" release --owner agent-b
  [ "$status" -eq 3 ]
  run "$SCRIPT" --help
  [[ "$output" == *"Exit 3"* ]]
  grep -q 'exit 3' "$BATS_TEST_DIRNAME/../docs/agent-browser-policy.md"
}

@test "TEMP_BROWSER_LAUNCH hook gets profile and port; its pid is recorded" {
  cat > "$TEST_DIR/hook" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${TEMP_BROWSER_STATE_DIR}/hook-args"
nohup sleep 300 >/dev/null 2>&1 </dev/null &
echo "launching" >&2
echo "$!"
STUB
  chmod +x "$TEST_DIR/hook"
  export TEMP_BROWSER_LAUNCH="$TEST_DIR/hook"
  run "$SCRIPT" acquire --owner a --reason r
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "9399" ]
  profile="$(cat "$TEMP_BROWSER_STATE_DIR/lock/profile")"
  [ "$(sed -n 1p "$TEMP_BROWSER_STATE_DIR/hook-args")" = "$profile" ]
  [ "$(sed -n 2p "$TEMP_BROWSER_STATE_DIR/hook-args")" = "9399" ]
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  kill -0 "$pid"
  [ ! -e "$TEMP_BROWSER_STATE_DIR/launch-args" ]
}

@test "TEMP_BROWSER_LAUNCH hook that prints no pid frees the lock" {
  printf '#!/bin/bash\necho nope\n' > "$TEST_DIR/hook"
  chmod +x "$TEST_DIR/hook"
  export TEMP_BROWSER_LAUNCH="$TEST_DIR/hook"
  run "$SCRIPT" acquire --owner a --reason r
  [ "$status" -eq 1 ]
  [ ! -e "$TEMP_BROWSER_STATE_DIR/lock" ]
}

@test "TEMP_BROWSER_HEADED=1 launches in the background without headless" {
  cat > "$TEST_DIR/fake-open" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "${TEMP_BROWSER_STATE_DIR}/open-args"
while [ "$#" -gt 0 ] && [ "$1" != "--args" ]; do shift; done
shift
nohup "$FAKE_CHROME_LOOP" "$@" >/dev/null 2>&1 </dev/null &
STUB
  cat > "$TEST_DIR/chrome-loop" <<'STUB'
#!/bin/bash
while :; do sleep 1; done
STUB
  chmod +x "$TEST_DIR/fake-open" "$TEST_DIR/chrome-loop"
  export FAKE_CHROME_LOOP="$TEST_DIR/chrome-loop"
  export TEMP_BROWSER_OPEN="$TEST_DIR/fake-open"
  export TEMP_BROWSER_HEADED=1
  run "$SCRIPT" acquire --owner a --reason r
  [ "$status" -eq 0 ]
  args="$TEMP_BROWSER_STATE_DIR/open-args"
  grep -qx -- '-g' "$args"
  grep -qx -- '-n' "$args"
  ! grep -q -- '--headless' "$args"
  grep -qx -- '--remote-debugging-port=9399' "$args"
  profile="$(cat "$TEMP_BROWSER_STATE_DIR/lock/profile")"
  pid="$(cat "$TEMP_BROWSER_STATE_DIR/lock/pid")"
  ps -p "$pid" -o command= | grep -q -- "--user-data-dir=$profile"
}

@test "headed launch never activates or raises" {
  ! grep -qE 'osascript|activate|open -a|open -n -a' "$SCRIPT"
  grep -q -- '-g -n -a' "$SCRIPT"
}

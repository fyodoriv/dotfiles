#!/usr/bin/env bats
# Tests for lib/lock.sh — lock acquisition, release, stale detection

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"
  export DOTFILES_LOCK="$TEST_DIR/.dotfiles.lock"
  LOCK_LIB="$BATS_TEST_DIRNAME/../lib/lock.sh"

  # lock.sh calls warn() from colors.sh — provide a stub
  warn() { echo "WARN: $1"; }
  export -f warn
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "lock.sh exists and is sourceable" {
  [ -f "$LOCK_LIB" ]
  source "$LOCK_LIB"
}

@test "acquire_lock creates lock file" {
  source "$LOCK_LIB"
  acquire_lock "test-caller"
  [ -f "$DOTFILES_LOCK" ]
}

@test "lock file contains PID on first line" {
  source "$LOCK_LIB"
  acquire_lock "test-caller"
  local lock_pid
  lock_pid=$(head -1 "$DOTFILES_LOCK")
  [ "$lock_pid" = "$$" ]
}

@test "lock file contains caller name on second line" {
  source "$LOCK_LIB"
  acquire_lock "my-script"
  local lock_caller
  lock_caller=$(sed -n '2p' "$DOTFILES_LOCK")
  [ "$lock_caller" = "my-script" ]
}

@test "acquire_lock defaults caller to 'unknown'" {
  source "$LOCK_LIB"
  acquire_lock
  local lock_caller
  lock_caller=$(sed -n '2p' "$DOTFILES_LOCK")
  [ "$lock_caller" = "unknown" ]
}

@test "release_lock removes lock file" {
  source "$LOCK_LIB"
  acquire_lock "test-caller"
  [ -f "$DOTFILES_LOCK" ]
  release_lock
  [ ! -f "$DOTFILES_LOCK" ]
}

@test "acquire_lock fails when held by a live process" {
  source "$LOCK_LIB"
  # Start a background sleep so we have a live PID that's definitely ours
  sleep 60 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "other-caller" > "$DOTFILES_LOCK"
  run acquire_lock "test-caller"
  kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"locked by other-caller"* ]]
}

@test "competing acquisitions allow only one winner" {
  local results_dir start_file worker worker_count
  results_dir="$TEST_DIR/results"
  start_file="$TEST_DIR/start"
  worker="$TEST_DIR/lock-worker.sh"
  worker_count=25
  mkdir -p "$results_dir"

  cat > "$worker" <<'EOF'
#!/usr/bin/env bash
set -u

warn() { :; }
source "$LOCK_LIB"

while [ ! -e "$START_FILE" ]; do
  sleep 0.01
done

if acquire_lock "$WORKER_NAME"; then
  printf 'success\n' > "$RESULTS_DIR/$WORKER_NAME"
  sleep 1
else
  printf 'fail\n' > "$RESULTS_DIR/$WORKER_NAME"
fi
EOF
  chmod +x "$worker"

  local pids=()
  local i
  for ((i = 1; i <= worker_count; i++)); do
    env \
      DOTFILES_LOCK="$DOTFILES_LOCK" \
      LOCK_LIB="$LOCK_LIB" \
      RESULTS_DIR="$results_dir" \
      START_FILE="$start_file" \
      WORKER_NAME="worker-$i" \
      bash "$worker" &
    pids+=("$!")
  done

  touch "$start_file"

  local pid
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  local successes failures total result_file result_value
  successes=0
  failures=0
  for result_file in "$results_dir"/*; do
    result_value=$(<"$result_file")
    case "$result_value" in
      success) successes=$((successes + 1)) ;;
      fail) failures=$((failures + 1)) ;;
    esac
  done

  total=$((successes + failures))
  [ "$total" -eq "$worker_count" ]
  [ "$successes" -eq 1 ]
  [ "$failures" -eq $((worker_count - 1)) ]
}

@test "a lock file still being written (empty, fresh) counts as held" {
  # acquire_lock creates the file, then writes the PID. Between the two, a
  # second caller saw an empty PID, took it as stale, and also won the lock.
  source "$LOCK_LIB"
  : > "$DOTFILES_LOCK"
  run acquire_lock "second-caller"
  [ "$status" -eq 1 ] || { echo "stole a lock that was still being written: $output"; return 1; }
  [ -f "$DOTFILES_LOCK" ]
  [ ! -s "$DOTFILES_LOCK" ]
}

@test "an empty lock file left by a crash is stale once it is old" {
  source "$LOCK_LIB"
  : > "$DOTFILES_LOCK"
  touch -t 202001010000 "$DOTFILES_LOCK"
  run acquire_lock "new-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale lock"* ]]
}

@test "acquire_lock steals stale lock (dead PID)" {
  source "$LOCK_LIB"
  # Use a PID that's certainly dead
  printf '%s\n%s\n' "99999" "dead-caller" > "$DOTFILES_LOCK"
  # Ensure that PID is actually dead (it almost certainly is)
  if kill -0 99999 2>/dev/null; then
    skip "PID 99999 is unexpectedly alive"
  fi
  run acquire_lock "new-caller"
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale lock"* ]]
}

@test "stale lock is replaced with new lock info" {
  source "$LOCK_LIB"
  printf '%s\n%s\n' "99999" "dead-caller" > "$DOTFILES_LOCK"
  if kill -0 99999 2>/dev/null; then
    skip "PID 99999 is unexpectedly alive"
  fi
  acquire_lock "replacement"
  local lock_pid lock_caller
  lock_pid=$(head -1 "$DOTFILES_LOCK")
  lock_caller=$(sed -n '2p' "$DOTFILES_LOCK")
  [ "$lock_pid" = "$$" ]
  [ "$lock_caller" = "replacement" ]
}

@test "acquire_lock steals an old lock whose PID was reused by a non-dotfiles process" {
  source "$LOCK_LIB"
  sleep 60 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "sync" > "$DOTFILES_LOCK"
  touch -t 202001010000 "$DOTFILES_LOCK"
  run acquire_lock "doctor"
  kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale lock"* ]]
  [[ "$output" == *"not a dotfiles process"* ]]
}

@test "acquire_lock keeps an old lock held by a live dotfiles process" {
  source "$LOCK_LIB"
  printf '#!/bin/bash\nsleep 60\n' > "$TEST_DIR/dotfiles-sync"
  chmod +x "$TEST_DIR/dotfiles-sync"
  "$TEST_DIR/dotfiles-sync" &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "sync" > "$DOTFILES_LOCK"
  touch -t 202001010000 "$DOTFILES_LOCK"
  run acquire_lock "doctor"
  kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [[ "$output" == *"locked by sync"* ]]
  [ "$(head -1 "$DOTFILES_LOCK")" = "$bg_pid" ]
}

@test "acquire_lock keeps a fresh lock held by a live non-dotfiles process" {
  source "$LOCK_LIB"
  sleep 60 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "sync" > "$DOTFILES_LOCK"
  run acquire_lock "doctor"
  kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null || true
  [ "$status" -eq 1 ]
  [ "$(head -1 "$DOTFILES_LOCK")" = "$bg_pid" ]
}

@test "DOTFILES_LOCK_MAX_AGE controls when a reused PID counts as stale" {
  source "$LOCK_LIB"
  sleep 60 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "sync" > "$DOTFILES_LOCK"
  sleep 2
  DOTFILES_LOCK_MAX_AGE=1 run acquire_lock "doctor"
  kill "$bg_pid" 2>/dev/null; wait "$bg_pid" 2>/dev/null || true
  [ "$status" -eq 0 ]
}

@test "release_lock is safe when no lock file exists" {
  source "$LOCK_LIB"
  [ ! -f "$DOTFILES_LOCK" ]
  release_lock
  [ ! -f "$DOTFILES_LOCK" ]
}

@test "DOTFILES_LOCK can be overridden via env" {
  CUSTOM_LOCK="$TEST_DIR/custom.lock"
  export DOTFILES_LOCK="$CUSTOM_LOCK"
  source "$LOCK_LIB"
  acquire_lock "custom-test"
  [ -f "$CUSTOM_LOCK" ]
  [ ! -f "$TEST_DIR/.dotfiles.lock" ] || [ "$CUSTOM_LOCK" = "$TEST_DIR/.dotfiles.lock" ]
}

@test "lock file has correct format (two lines)" {
  source "$LOCK_LIB"
  acquire_lock "format-test"
  local line_count
  line_count=$(wc -l < "$DOTFILES_LOCK")
  [ "$line_count" -eq 2 ]
}

@test "wait_for_lock steals stale lock then acquires" {
  source "$LOCK_LIB"
  printf '%s\n%s\n' "99999" "dead-caller" > "$DOTFILES_LOCK"
  wait_for_lock "apply" 5
  [ -f "$DOTFILES_LOCK" ]
  lock_caller=$(sed -n '2p' "$DOTFILES_LOCK")
  [ "$lock_caller" = "apply" ]
  release_lock
}

@test "wait_for_lock fails when live process holds lock" {
  source "$LOCK_LIB"
  sleep 30 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "other-caller" > "$DOTFILES_LOCK"
  run wait_for_lock "apply" 2
  [ "$status" -eq 1 ]
  kill "$bg_pid" 2>/dev/null || true
  wait "$bg_pid" 2>/dev/null || true
}

@test "wait_for_lock says once that it waits, updates at most every 30 s, and says when it gives up" {
  source "$LOCK_LIB"
  sleep 30 &
  local bg_pid=$!
  printf '%s\n%s\n' "$bg_pid" "upgrade" > "$DOTFILES_LOCK"
  # 4 s between updates instead of 30 keeps the test short.
  DOTFILES_LOCK_NOTE_EVERY=4 run wait_for_lock "apply" 9
  kill "$bg_pid" 2>/dev/null || true
  wait "$bg_pid" 2>/dev/null || true
  echo "$output"
  [ "$status" -eq 1 ]
  [ "$(grep -c 'Waiting for the lock held by upgrade (pid '"$bg_pid"')' <<< "$output")" -eq 1 ]
  [ "$(grep -c 'Still waiting' <<< "$output")" -eq 2 ]
  [ "$(grep -c 'Timed out after 9s' <<< "$output")" -eq 1 ]
  [ "$(grep -c 'Skipping' <<< "$output")" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
}

@test "wait_for_lock stops at once when the lock cannot be made" {
  source "$LOCK_LIB"
  DOTFILES_LOCK="$TEST_DIR/missing/.dotfiles.lock"
  SECONDS=0
  run wait_for_lock "apply" 20
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 5 ]
  [ "$(grep -c 'Cannot create lock' <<< "$output")" -eq 1 ]
  [[ "$output" != *Waiting* ]]
}

@test "a folder at the lock path is never acquired (ln would link inside it)" {
  source "$LOCK_LIB"
  mkdir -p "$DOTFILES_LOCK"
  run acquire_lock "apply"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is a directory"* ]]
  [ -z "$(ls -A "$DOTFILES_LOCK")" ]
  SECONDS=0
  run wait_for_lock "apply" 20
  [ "$status" -eq 1 ]
  [ "$SECONDS" -lt 5 ]
  [ -z "$(ls -A "$DOTFILES_LOCK")" ]
}

@test "wait_for_lock prints nothing when the lock is free" {
  source "$LOCK_LIB"
  run wait_for_lock "apply" 5
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "lib/lock.sh shellcheck disable lines carry an inline rationale" {
  # Convention: every `# shellcheck disable=CODE` in lib/lock.sh must end
  # with `# <reason>` so a future reader (or auto-fix tool) knows why
  # the disable is intentional.
  #
  # The SC2064 disable in particular is non-obvious: the trap deliberately
  # expands $DOTFILES_LOCK at registration time so cleanup still works
  # after the variable is unset. Stripping that comment loses the
  # rationale and invites a "fix" that breaks lock cleanup.
  local lib="$BATS_TEST_DIRNAME/../lib/lock.sh"
  local bad
  bad=$(grep -nE '# shellcheck disable=' "$lib" | grep -vE 'disable=[^ ]+ +# .+' || true)
  [ -z "$bad" ] || {
    echo "lib/lock.sh has shellcheck disable lines without inline rationale:"
    echo "$bad"
    echo "convention: '# shellcheck disable=CODE # <reason>'"
    return 1
  }
}

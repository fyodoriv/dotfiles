#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_DATA_HOME="$TEST_DIR/data" XDG_CONFIG_HOME="$TEST_DIR/config"
  export DOTFILES_STATS_LOG=1 DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" NATIVE_LOG="$TEST_DIR/native.log" PGREP_LOG="$TEST_DIR/pgrep.log"
  export TEST_ROOT="$TEST_DIR/repo"
  mkdir -p "$HOME" "$TEST_ROOT/bin" "$TEST_ROOT/lib" "$TEST_ROOT/rust/app-priority/target/release" "$TEST_DIR/mockbin"
  cp "$BATS_TEST_DIRNAME/../bin/app-priority-native" "$TEST_ROOT/bin/"
  cp "$BATS_TEST_DIRNAME/../lib/native-delivery.sh" "$TEST_ROOT/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/app-priority-build.sh" "$TEST_ROOT/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/app-priority-toolchain.sh" "$TEST_ROOT/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/lock.sh" "$TEST_ROOT/lib/"
  cat > "$TEST_ROOT/bin/heavy-run" <<'MOCK'
#!/bin/bash
[ "${FAIL_BUILD:-0}" = 0 ]
MOCK
  cat > "$TEST_ROOT/rust/app-priority/target/release/dotfiles-app-priority" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$NATIVE_LOG"
exit "${NATIVE_EXIT:-0}"
MOCK
  cat > "$TEST_DIR/mockbin/uname" <<'MOCK'
#!/bin/bash
case "$1" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' x86_64 ;;
esac
MOCK
  cat > "$TEST_DIR/mockbin/curl" <<'MOCK'
#!/bin/bash
echo 'fixture must never fetch a toolchain' >&2
exit 99
MOCK
  cat > "$TEST_DIR/mockbin/pgrep" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" >> "$PGREP_LOG"
exit 1
MOCK
  chmod +x "$TEST_ROOT/bin/heavy-run" "$TEST_ROOT/rust/app-priority/target/release/dotfiles-app-priority" "$TEST_DIR/mockbin/"*
  export PATH="$TEST_DIR/mockbin:$PATH"
  INSTALLER="$TEST_ROOT/bin/app-priority-native"
  COMMAND="$BATS_TEST_DIRNAME/../bin/app-priority"
  DIRECTORY="$XDG_DATA_HOME/dotfiles/native/app-priority"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "install dispatches once and preserves the stats record" {
  run "$INSTALLER" install
  [ "$status" -eq 0 ]
  run "$INSTALLER" install
  [ "$status" -eq 0 ]
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$NATIVE_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(cat "$NATIVE_LOG")" = --apply ]
  [ ! -e "$PGREP_LOG" ]
  run jq -e 'select(.task == "app-priority" and .ok == true and .runtime == "rust")' "$DOTFILES_STATS_FILE"
  [ "$status" -eq 0 ]
}

@test "a missing native selection requests install and runs no priority actions" {
  run "$COMMAND"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dotfiles priority-native install"* ]]
  [ ! -e "$NATIVE_LOG" ]
  [ ! -s "$PGREP_LOG" ]
}

@test "a missing selection with a legacy rollback hold stays inactive" {
  mkdir -p "$DIRECTORY"
  touch "$DIRECTORY/disabled"
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ ! -e "$NATIVE_LOG" ]
  [ ! -s "$PGREP_LOG" ]
  [ -f "$DIRECTORY/disabled" ]
}

@test "a corrupt native selection requests install and runs no priority actions" {
  "$INSTALLER" install
  printf 'corrupt\n' >> "$DIRECTORY/$(readlink "$DIRECTORY/current")"
  run "$COMMAND"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dotfiles priority-native install"* ]]
  [ ! -e "$NATIVE_LOG" ]
  [ ! -s "$PGREP_LOG" ]
  [ ! -e "$DOTFILES_STATS_FILE" ]
}

@test "failed native execution never repeats actions through the shell" {
  "$INSTALLER" install
  export NATIVE_EXIT=9
  run "$COMMAND"
  [ "$status" -eq 9 ]
  [ ! -e "$PGREP_LOG" ]
  run jq -e 'select(.task == "app-priority" and .ok == false and .runtime == "rust")' "$DOTFILES_STATS_FILE"
  [ "$status" -eq 0 ]
}

@test "disabled stats do not record the native runtime" {
  "$INSTALLER" install
  export DOTFILES_STATS_LOG=0
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ ! -e "$DOTFILES_STATS_FILE" ]
}

@test "a failed build keeps the prior install and disable pauses App Priority" {
  "$INSTALLER" install
  original="$(readlink "$DIRECTORY/current")"
  export FAIL_BUILD=1
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$original" ]
  "$INSTALLER" rollback --disable
  [ ! -L "$DIRECTORY/current" ]
  [ -f "$DIRECTORY/disabled" ]
  run "$INSTALLER" refresh
  [ "$status" -eq 0 ]
  [ ! -L "$DIRECTORY/current" ]
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ ! -s "$PGREP_LOG" ]
}

@test "disable refuses to remove an unrelated link" {
  mkdir -p "$DIRECTORY"
  ln -s elsewhere "$DIRECTORY/current"
  run "$INSTALLER" rollback --disable
  [ "$status" -ne 0 ]
  [ -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/disabled" ]
}

@test "Cargo outputs are ignored but source stays visible" {
  run git -C "$BATS_TEST_DIRNAME/.." check-ignore --no-index rust/app-priority/target/example
  [ "$status" -eq 0 ]
  run git -C "$BATS_TEST_DIRNAME/.." check-ignore --no-index rust/app-priority/src/main.rs
  [ "$status" -ne 0 ]
}

@test "an interrupted copy leaves the previous install selected" {
  "$INSTALLER" install
  original="$(readlink "$DIRECTORY/current")"
  cat > "$TEST_DIR/mockbin/cp" <<'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$TEST_DIR/mockbin/cp"
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$original" ]
}

stub_pinned_toolchain() {
  local compiler="$DIRECTORY/toolchain/rustup/toolchains/1.100.0-x86_64-apple-darwin/bin"
  local proxy="$DIRECTORY/toolchain/cargo/bin"
  mkdir -p "$compiler" "$proxy"
  printf '#!/bin/bash\nexit 97\n' > "$compiler/rustc"
  printf '#!/bin/bash\nexit 0\n' > "$compiler/cargo"
  cp "$compiler/cargo" "$proxy/cargo"
  cat > "$proxy/rustc" <<'MOCK'
#!/bin/bash
[ "$RUSTUP_TOOLCHAIN" = 1.100.0-x86_64-apple-darwin ] && [ "$RUSTUP_AUTO_INSTALL" = 0 ] || exit 98
echo "rustc 1.100.0 (fixture)"
MOCK
  chmod +x "$compiler/rustc" "$compiler/cargo" "$proxy/cargo" "$proxy/rustc"
}

@test "first setup probes without applying and publishes only a verified binary" {
  stub_pinned_toolchain

  run env NATIVE_EXIT=9 "$INSTALLER" ensure fixture-source
  [ "$status" -ne 0 ]
  [ ! -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/source-hash" ]

  run env NATIVE_EXIT=2 "$INSTALLER" ensure fixture-source
  [ "$status" -eq 0 ]
  [ -L "$DIRECTORY/current" ]
  [ "$(cat "$DIRECTORY/source-hash")" = fixture-source ]
  [ "$(wc -l < "$NATIVE_LOG" | tr -d ' ')" -eq 2 ]
  [ -z "$(tr -d '\n' < "$NATIVE_LOG")" ]
}

@test "first setup respects a rollback from before the disabled marker" {
  "$INSTALLER" install
  rm "$DIRECTORY/current"
  run "$INSTALLER" ensure fixture-source
  [ "$status" -eq 0 ]
  [ ! -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/toolchain" ]
}

stub_in_progress_first_build() {
  stub_pinned_toolchain
  cat > "$TEST_ROOT/bin/heavy-run" <<'MOCK'
#!/bin/bash
if [ "${FIXTURE_IGNORE_BUILD_TERM:-0}" = 1 ]; then trap '' TERM; fi
ps -o pgid= -p "$$" | tr -d '[:space:]' > "$TEST_ROOT/worker-pid.tmp"
mv "$TEST_ROOT/worker-pid.tmp" "$TEST_ROOT/build-started"
for ((try = 0; try < 80; try++)); do
  [ ! -f "$TEST_ROOT/release-build" ] || exit 0
  sleep 0.1
done
exit 1
MOCK
}

@test "disable waits for a first build and leaves App Priority paused" {
  stub_in_progress_first_build
  NATIVE_EXIT=2 DOTFILES_NATIVE_BUILD_MAX_WAIT=10 "$INSTALLER" ensure fixture-source > "$TEST_ROOT/ensure.log" 2>&1 &
  ensure_pid=$!
  for ((try = 0; try < 30; try++)); do
    [ ! -f "$TEST_ROOT/build-started" ] || break
    sleep 0.1
  done
  [ -f "$TEST_ROOT/build-started" ]
  DOTFILES_NATIVE_BUILD_MAX_WAIT=10 "$INSTALLER" rollback --disable > "$TEST_ROOT/rollback.log" 2>&1 &
  rollback_pid=$!
  for ((try = 0; try < 30; try++)); do
    if grep -q 'Waiting for the lock held by app-priority-ensure' "$TEST_ROOT/rollback.log"; then break; fi
    sleep 0.1
  done
  grep -q 'Waiting for the lock held by app-priority-ensure' "$TEST_ROOT/rollback.log"
  touch "$TEST_ROOT/release-build"
  wait "$ensure_pid"
  wait "$rollback_pid"
  [ -f "$DIRECTORY/disabled" ]
  [ ! -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/.install.lock" ]
}

start_fixture_first_build() {
  stub_in_progress_first_build
  NATIVE_EXIT=2 DOTFILES_NATIVE_BUILD_MAX_WAIT=12 "$INSTALLER" ensure fixture-source > "$TEST_ROOT/ensure.log" 2>&1 3>&- &
  ensure_pid=$!
  for ((try = 0; try < 30; try++)); do
    [ ! -s "$TEST_ROOT/build-started" ] || break
    sleep 0.1
  done
  worker_pid="$(cat "$TEST_ROOT/build-started")"
  [[ "$worker_pid" =~ ^[1-9][0-9]+$ && "$worker_pid" != "$ensure_pid" ]]
  kill -0 "$worker_pid"
}

start_fixture_rollback() {
  DOTFILES_NATIVE_BUILD_MAX_WAIT=12 "$INSTALLER" rollback --disable > "$TEST_ROOT/rollback.log" 2>&1 3>&- &
  rollback_pid=$!
  for ((try = 0; try < 30; try++)); do
    if grep -Eq 'Waiting for the lock|App Priority paused' "$TEST_ROOT/rollback.log"; then break; fi
    sleep 0.1
  done
  grep -Eq 'Waiting for the lock|App Priority paused' "$TEST_ROOT/rollback.log"
}

@test "an interrupted first install cannot select a binary after rollback succeeds" {
  start_fixture_first_build
  kill -KILL "$ensure_pid"
  wait "$ensure_pid" 2>/dev/null || true

  start_fixture_rollback
  touch "$TEST_ROOT/release-build"
  wait "$rollback_pid"
  for ((try = 0; try < 50; try++)); do
    ! kill -0 "$worker_pid" 2>/dev/null && break
    sleep 0.1
  done
  if kill -0 "$worker_pid" 2>/dev/null; then
    echo 'The first-install worker did not exit.' >&2
    return 1
  fi
  [ -f "$DIRECTORY/disabled" ]
  [ ! -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/.install.lock" ]
}

fixture_build_group_alive() {
  ps -ax -o pgid= -o stat= | awk -v group="$worker_pid" '$1 == group && $2 !~ /^Z/ { found = 1 } END { exit !found }'
}

@test "a killed first-install worker cannot leave a later selection or running children" {
  start_fixture_first_build
  [ "$(head -1 "$DIRECTORY/.install.lock")" = "$worker_pid" ]
  kill -KILL "$worker_pid"

  start_fixture_rollback
  touch "$TEST_ROOT/release-build"
  if wait "$ensure_pid" 2>/dev/null; then
    echo 'The launcher reported success after its worker was killed.' >&2
    return 1
  fi
  wait "$rollback_pid"
  for ((try = 0; try < 50; try++)); do
    if ! fixture_build_group_alive; then break; fi
    sleep 0.1
  done
  if fixture_build_group_alive; then
    echo 'The first-install worker left running children.' >&2
    return 1
  fi
  [ -f "$DIRECTORY/disabled" ]
  [ ! -L "$DIRECTORY/current" ]
  [ ! -e "$DIRECTORY/.install.lock" ]
}

@test "the first-install launcher drains its group on worker failure" {
  export FIXTURE_IGNORE_BUILD_TERM=1
  start_fixture_first_build
  [ "$(head -1 "$DIRECTORY/.install.lock")" = "$worker_pid" ]
  kill -KILL "$worker_pid"
  if wait "$ensure_pid" 2>/dev/null; then
    echo 'The launcher reported success after its worker was killed.' >&2
    return 1
  fi
  if fixture_build_group_alive; then
    touch "$TEST_ROOT/release-build"
    echo 'The launcher returned with its build processes still running.' >&2
    return 1
  fi
  [ ! -L "$DIRECTORY/current" ]
}

install_priority_variant() {
  printf '\n# fixture %s\n' "$1" >> "$TEST_ROOT/rust/app-priority/target/release/dotfiles-app-priority"
  "$INSTALLER" install
}

@test "native rollback refuses a first generation without a predecessor" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
}

@test "native rollback selects the verified immediate predecessor" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  second="$(readlink "$DIRECTORY/current")"
  [ "$second" != "$first" ]

  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
  [ -x "$DIRECTORY/$second" ]
}

@test "plain rollback selects the verified predecessor for the next launch" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  run env NATIVE_EXIT=2 "$INSTALLER" rollback
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
  [ -f "$DIRECTORY/disabled" ]
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ "$(tail -1 "$NATIVE_LOG")" = --apply ]
  [ ! -s "$PGREP_LOG" ]
}

@test "native rollback stays selected across an automatic refresh" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  env NATIVE_EXIT=2 "$INSTALLER" rollback --native

  run "$INSTALLER" refresh new-fixture-source
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
}

@test "native rollback preserves the predecessor after a failed build or selection" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  second="$(readlink "$DIRECTORY/current")"

  run env FAIL_BUILD=1 "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$second" ]

  printf '\n# candidate that never became current\n' >> "$TEST_ROOT/rust/app-priority/target/release/dotfiles-app-priority"
  cat > "$TEST_DIR/mockbin/ln" <<'MOCK'
#!/bin/bash
if [[ "$1" == -s && "$3" == */.current.* ]]; then exit 1; fi
exec /bin/ln "$@"
MOCK
  chmod +x "$TEST_DIR/mockbin/ln"
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$second" ]

  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$second" ]
  [ ! -e "$DIRECTORY/disabled" ]
  touch "$DIRECTORY/disabled"
  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -ne 0 ]
  [ -f "$DIRECTORY/disabled" ]
  rm "$DIRECTORY/disabled"
  rm "$TEST_DIR/mockbin/ln"

  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
}

@test "native rollback refuses a corrupted predecessor and keeps current" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  second="$(readlink "$DIRECTORY/current")"
  printf 'corrupt\n' >> "$DIRECTORY/$first"

  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$second" ]
}

@test "native rollback keeps the predecessor across an identical build" {
  install_priority_variant first
  first="$(readlink "$DIRECTORY/current")"
  install_priority_variant second
  second="$(readlink "$DIRECTORY/current")"
  "$INSTALLER" install
  [ "$(readlink "$DIRECTORY/current")" = "$second" ]

  run env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
}

@test "native rollback hold ends after an explicit native install" {
  install_priority_variant first
  install_priority_variant second
  env NATIVE_EXIT=2 "$INSTALLER" rollback --native
  first="$(readlink "$DIRECTORY/current")"
  rm "$DIRECTORY/disabled"
  mkdir "$DIRECTORY/disabled"
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
  rmdir "$DIRECTORY/disabled"
  touch "$DIRECTORY/disabled"

  cat > "$TEST_DIR/mockbin/rm" <<'SCRIPT'
#!/bin/bash
if [[ "$1" == -f && "$2" == */disabled ]]; then exit 1; fi
exec /bin/rm "$@"
SCRIPT
  chmod +x "$TEST_DIR/mockbin/rm"
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$first" ]
  [ -f "$DIRECTORY/disabled" ]
  /bin/rm "$TEST_DIR/mockbin/rm"

  install_priority_variant third
  third="$(readlink "$DIRECTORY/current")"
  [ "$third" != "$first" ]

  printf '\n# refresh after an explicit install\n' >> "$TEST_ROOT/rust/app-priority/target/release/dotfiles-app-priority"
  run "$INSTALLER" refresh fresh-fixture-source
  [ "$status" -eq 0 ]
  [ "$(readlink "$DIRECTORY/current")" != "$third" ]
  [ "$(cat "$DIRECTORY/source-hash")" = fresh-fixture-source ]
}

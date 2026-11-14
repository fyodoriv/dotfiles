#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_DATA_HOME="$TEST_DIR/data" XDG_CONFIG_HOME="$TEST_DIR/config"
  export DOTFILES_STATS_LOG=1 DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl" NATIVE_LOG="$TEST_DIR/native.log" PGREP_LOG="$TEST_DIR/pgrep.log"
  export TEST_ROOT="$TEST_DIR/repo"
  mkdir -p "$HOME" "$TEST_ROOT/bin" "$TEST_ROOT/rust/app-priority/target/release" "$TEST_DIR/mockbin"
  cp "$BATS_TEST_DIRNAME/../bin/app-priority-native" "$TEST_ROOT/bin/"
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
printf '%s\n' Darwin
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

@test "a corrupted binary falls back before it can run" {
  "$INSTALLER" install
  printf 'corrupt\n' >> "$DIRECTORY/$(readlink "$DIRECTORY/current")"
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ ! -e "$NATIVE_LOG" ]
  [ -s "$PGREP_LOG" ]
  run jq -e 'select(.task == "app-priority" and .runtime == "shell")' "$DOTFILES_STATS_FILE"
  [ "$status" -eq 0 ]
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

@test "a failed build keeps the prior install and rollback restores shell" {
  "$INSTALLER" install
  original="$(readlink "$DIRECTORY/current")"
  export FAIL_BUILD=1
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$original" ]
  "$INSTALLER" rollback
  [ ! -L "$DIRECTORY/current" ]
  run "$COMMAND"
  [ "$status" -eq 0 ]
  [ -s "$PGREP_LOG" ]
}

@test "rollback refuses to remove an unrelated link" {
  mkdir -p "$DIRECTORY"
  ln -s elsewhere "$DIRECTORY/current"
  run "$INSTALLER" rollback
  [ "$status" -ne 0 ]
  [ -L "$DIRECTORY/current" ]
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

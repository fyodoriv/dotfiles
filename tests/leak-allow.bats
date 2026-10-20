#!/usr/bin/env bats
# lib/leak-allow.sh and `dotfiles leak allow --once` (issue #145, step 9).

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export XDG_STATE_HOME="$TEST_DIR/state"
}

teardown() {
  rm -rf "$TEST_DIR"
}

grant() {
  mkdir -p "$XDG_STATE_HOME/dotfiles"
  printf '%s %s\n' "$1" "$(( $(date +%s) + ${2:-600} ))" > "$XDG_STATE_HOME/dotfiles/leak-allow-once"
}

consume() {
  bash -c 'source "$1/lib/leak-allow.sh"; shift; leak_allow_consume "$@"' _ "$REPO_ROOT" "$@"
}

@test "leak allow is refused without a terminal" {
  run bash "$REPO_ROOT/bin/dotfiles-leak" allow --once < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"refused without a terminal"* ]]
  [ ! -f "$XDG_STATE_HOME/dotfiles/leak-allow-once" ]
}

@test "a sha grant matches only that push, once" {
  grant abc1234
  run consume deadbeef00
  [ "$status" -ne 0 ]
  run consume abc1234ffffffff
  [ "$status" -eq 0 ]
  run consume abc1234ffffffff
  [ "$status" -ne 0 ]
}

@test "an any grant does not cover a push, and expires" {
  grant any
  run consume abc1234ffff
  [ "$status" -ne 0 ]
  grant any -1
  run consume any
  [ "$status" -ne 0 ]
  [ ! -f "$XDG_STATE_HOME/dotfiles/leak-allow-once" ]
}

#!/usr/bin/env bats
# lib/updates-landed.sh and bin/dotfiles-updates-landed (#301): the update
# LaunchAgents record what they changed, so an agent (an agentbrew
# SessionStart hook) can say "updates landed, run the checkup" once a day
# until the checkup acknowledges them.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_STATE_HOME="$TEST_DIR/state"
  mkdir -p "$HOME"
  LIB="$BATS_TEST_DIRNAME/../lib/updates-landed.sh"
  CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-updates-landed"
}
teardown() { rm -rf "$TEST_DIR"; }

@test "nothing recorded: the nudge prints nothing" {
  run "$CLI"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recorded updates give one nudge a day, until --ack" {
  bash -c 'source "$1"; updates_landed_record tooling-sync "agentbrew: abc1234..def5678"; updates_landed_record dotfiles-upgrade "software upgraded"' _ "$LIB"
  run "$CLI"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 update(s) landed"* ]]
  [[ "$output" == *"tooling-checkup"* ]]
  run "$CLI"
  [ -z "$output" ]
  run "$CLI" --always
  [[ "$output" == *"2 update(s) landed"* ]]
  run "$CLI" --ack
  [ "$status" -eq 0 ]
  run "$CLI" --always
  [ -z "$output" ]
}

@test "the update jobs record what landed" {
  grep -q 'updates_landed_record tooling-sync' "$BATS_TEST_DIRNAME/../bin/tooling-sync"
  grep -q 'updates_landed_record dotfiles-upgrade' "$BATS_TEST_DIRNAME/../bin/dotfiles-upgrade"
}

@test "the nudge still works after the record is trimmed (more than 200 updates)" {
  bash -c 'source "$1"; for i in $(seq 205); do updates_landed_record tooling-sync "x $i"; done' _ "$LIB"
  run "$CLI" --ack
  sleep 1
  bash -c 'source "$1"; updates_landed_record dotfiles-upgrade "software upgraded"' _ "$LIB"
  run "$CLI" --always
  echo "$output"
  [[ "$output" == *"1 update(s) landed"*"dotfiles-upgrade"* ]]
}

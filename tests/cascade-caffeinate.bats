#!/usr/bin/env bats
# Tests for bin/cascade-caffeinate (deprecated wrapper)

@test "cascade-caffeinate: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/cascade-caffeinate" ]
}

@test "cascade-caffeinate: valid bash syntax" {
  run bash -n "$BATS_TEST_DIRNAME/../bin/cascade-caffeinate"
  [ "$status" -eq 0 ]
}

@test "cascade-caffeinate: delegates to dotfiles-agent-keepawake" {
  content=$(cat "$BATS_TEST_DIRNAME/../bin/cascade-caffeinate")
  [[ "$content" == *"dotfiles-agent-keepawake"* ]]
}

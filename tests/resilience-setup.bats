#!/usr/bin/env bats
# Tests for bin/dotfiles-resilience-setup

load test_helper

@test "resilience-setup: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" ]
}

@test "resilience-setup: --help prints usage" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"resilience"* ]] || [[ "$output" == *"sleep"* ]] || [[ "$output" == *"tmux"* ]]
}

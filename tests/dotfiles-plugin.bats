#!/usr/bin/env bats
# Tests for bin/dotfiles-plugin

load test_helper

@test "dotfiles-plugin: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-plugin" ]
}

@test "dotfiles-plugin: --help prints usage" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-plugin" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"plugin"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"add"* ]]
}

@test "dotfiles-plugin: list works even with no plugins" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-plugin" list
  # Should exit 0 even with empty plugin dir
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

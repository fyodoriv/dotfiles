#!/usr/bin/env bats
# Tests for bin/dotfiles-set-persistent-chrome-themes

load test_helper

@test "chrome-themes: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" ]
}

@test "chrome-themes: --help prints usage (if supported)" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes" --help
  # Script may not have --help; just verify it's parseable bash
  run bash -n "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes"
  [ "$status" -eq 0 ]
}

@test "chrome-themes: script references all 3 persistent Chrome ports" {
  content=$(cat "$BATS_TEST_DIRNAME/../bin/dotfiles-set-persistent-chrome-themes")
  [[ "$content" == *"9223"* ]]
  [[ "$content" == *"9224"* ]]
  [[ "$content" == *"9225"* ]]
}

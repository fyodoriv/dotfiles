#!/usr/bin/env bats
# Tests for bin/cheat — quick cheatsheet reference

load test_helper

CHEAT_CMD="$BATS_TEST_DIRNAME/../bin/cheat"

@test "cheat script exists and is executable" {
  [ -f "$CHEAT_CMD" ]
  [ -x "$CHEAT_CMD" ]
}

@test "cheat script has correct shebang" {
  head -1 "$CHEAT_CMD" | grep -q '#!/bin/bash'
}

@test "cheat with no args shows all sections" {
  run bash "$CHEAT_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell Commands"* ]]
  [[ "$output" == *"Git Commands"* ]]
  [[ "$output" == *"IdeaVim"* ]]
  [[ "$output" == *"fzf Shortcuts"* ]]
  [[ "$output" == *"Line Editing"* ]]
  [[ "$output" == *"Modern CLI Tools"* ]]
}

@test "cheat shows filter hint at the bottom" {
  run bash "$CHEAT_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Filter: cheat"* ]]
}

@test "cheat git shows only git section" {
  run bash "$CHEAT_CMD" git
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git Commands"* ]]
  [[ "$output" != *"Shell Commands"* ]]
  [[ "$output" != *"IdeaVim"* ]]
}

@test "cheat vim shows only vim section" {
  run bash "$CHEAT_CMD" vim
  [ "$status" -eq 0 ]
  [[ "$output" == *"IdeaVim"* ]]
  [[ "$output" != *"Shell Commands"* ]]
  [[ "$output" != *"Git Commands"* ]]
}

@test "cheat fzf shows only fzf section" {
  run bash "$CHEAT_CMD" fzf
  [ "$status" -eq 0 ]
  [[ "$output" == *"fzf Shortcuts"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat shell shows only shell section" {
  run bash "$CHEAT_CMD" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell Commands"* ]]
  [[ "$output" == *"Dotfiles Management"* ]]
  [[ "$output" != *"IdeaVim"* ]]
}

@test "cheat keys shows only keys section" {
  run bash "$CHEAT_CMD" keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"Line Editing"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat tools shows only tools section" {
  run bash "$CHEAT_CMD" tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modern CLI Tools"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat --help prints usage" {
  run bash "$CHEAT_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cheatsheet"* ]] || [[ "$output" == *"cheat"* ]]
}

@test "cheat shell lists key commands" {
  run bash "$CHEAT_CMD" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"killport"* ]]
  [[ "$output" == *"morning"* ]]
  [[ "$output" == *"cleanup"* ]]
  [[ "$output" == *"dotfiles doctor"* ]]
}

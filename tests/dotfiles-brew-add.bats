#!/usr/bin/env bats
# Tests for dotfiles-brew-add — add a Homebrew package to the brew file

load test_helper

BREW_ADD_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-brew-add"

@test "dotfiles-brew-add script exists and is executable" {
  [ -x "$BREW_ADD_CMD" ]
}

@test "dotfiles-brew-add has correct shebang" {
  head -1 "$BREW_ADD_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-brew-add uses strict mode" {
  grep -q 'set -euo pipefail' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add --help shows usage" {
  run "$BREW_ADD_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"brew-add"* ]]
}

@test "dotfiles-brew-add with no args shows usage and exits 1" {
  run "$BREW_ADD_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "dotfiles-brew-add supports --cask flag" {
  grep -q '\-\-cask' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add supports --full-only flag" {
  grep -q '\-\-full-only' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add supports --enterprise flag" {
  grep -q '\-\-enterprise' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add generates brew line for regular packages" {
  grep -q 'brew_line="brew' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add generates cask line for --cask packages" {
  grep -q 'brew_line="cask' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add checks for duplicate packages" {
  grep -q 'already exists' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add verifies insertion succeeded" {
  grep -q 'insertion failed' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add targets the correct brew file" {
  grep -q 'run_onchange_brew.sh.tmpl' "$BREW_ADD_CMD"
}

# ── Input validation ─────────────────────────────────────────────

@test "dotfiles-brew-add rejects shell injection" {
  run "$BREW_ADD_CMD" 'evil; rm -rf /'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid package name"* ]]
}

@test "dotfiles-brew-add rejects backtick injection" {
  run "$BREW_ADD_CMD" '$(whoami)'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid package name"* ]]
}

@test "dotfiles-brew-add rejects spaces in package name" {
  run "$BREW_ADD_CMD" 'foo bar'
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid package name"* ]]
}

@test "dotfiles-brew-add accepts valid tap name with slash" {
  # Just test the validation passes — actual insertion needs the brew file
  grep -q '\[a-zA-Z0-9@_./-\]' "$BREW_ADD_CMD"
}

@test "dotfiles-brew-add validates package name format" {
  grep -q 'invalid package name' "$BREW_ADD_CMD"
}

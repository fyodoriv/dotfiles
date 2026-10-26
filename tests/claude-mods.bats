#!/usr/bin/env bats
# Tests for .chezmoiscripts/run_after_claude-mods.sh and the claude.mods
# doctor check. Every test runs in a scratch HOME (test-process scope,
# removed in teardown) with a fake claude CLI that logs its arguments.

load test_helper

SCRIPT_REL=".chezmoiscripts/run_after_claude-mods.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export DOTFILES_DIR="$TEST_DIR/dotfiles"
  export AGENTBREW_DIR="$TEST_DIR/agentbrew"
  mkdir -p "$HOME/.local/bin" "$DOTFILES_DIR/.chezmoiscripts" "$TEST_DIR/bin" "$AGENTBREW_DIR/mods/.claude-plugin"
  echo '{"name":"agentbrew-mods","plugins":[]}' > "$AGENTBREW_DIR/mods/.claude-plugin/marketplace.json"
  cp "$BATS_TEST_DIRNAME/../$SCRIPT_REL" "$DOTFILES_DIR/$SCRIPT_REL"
  unset DOTFILES_CLAUDE_MODS DOTFILES_REPOS_DIR
  LOG="$TEST_DIR/claude.log"
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$LOG" > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  # No chezmoi data in a scratch HOME: the built-in default applies.
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "by default it adds the agentbrew mods marketplace and installs work-pane" {
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed: work-pane"* ]]
  grep -qx "plugin marketplace add $AGENTBREW_DIR/mods" "$LOG"
  grep -qx "plugin install work-pane@agentbrew-mods" "$LOG"
}

@test "an empty DOTFILES_CLAUDE_MODS installs nothing" {
  DOTFILES_CLAUDE_MODS="" run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ ! -e "$LOG" ]
}

@test "with no agentbrew mods folder it skips with one line and calls nothing" {
  rm -rf "$AGENTBREW_DIR/mods"
  export DOTFILES_REPOS_DIR="$TEST_DIR/none"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped"* ]]
  [ ! -e "$LOG" ]
}

@test "a failed install is reported and does not fail the apply" {
  printf '#!/bin/sh\ncase "$*" in *install*) exit 1;; esac\n' > "$HOME/.local/bin/claude"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"work-pane did not install"* ]]
}

@test "--print-list prints the resolved list" {
  DOTFILES_CLAUDE_MODS="work-pane, other" run bash "$DOTFILES_DIR/$SCRIPT_REL" --print-list
  [ "$output" = "$(printf 'work-pane\nother')" ]
}

#!/usr/bin/env bats
# use_cursor (chezmoi data, default true) turns every dotfiles-managed Cursor
# surface off: chezmoi scripts, Cursor-only LaunchAgents, the doctor module,
# and agentbrew's Cursor target (see overlay-root-agentfile.bats).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  REPO="$BATS_TEST_DIRNAME/.."
  mkdir -p "$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_render_launchagents() {
  chezmoi execute-template --source "$REPO" \
    --override-data "{\"profile\":\"full\",\"use_cursor\":$1}" \
    < "$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

# Load the rendered script's settings and helper functions without running it.
_load_launchagent_helpers() {
  local script="$1"
  eval "$(printf '%s\n' "$script" | grep -E '^(PROFILE|AUTO_UPGRADE|USE_CURSOR)=')"
  eval "$(printf '%s\n' "$script" | sed -n '/^should_skip_agent() {/,/^}/p')"
  eval "$(printf '%s\n' "$script" | sed -n '/^remove_skipped_agent() {/,/^}/p')"
}

@test "chezmoi config template declares use_cursor with default true" {
  grep -q 'promptBoolOnce . "use_cursor" ".*" true' "$REPO/.chezmoi.yaml.tmpl"
  grep -q '^  use_cursor: {{ $useCursor }}' "$REPO/.chezmoi.yaml.tmpl"
}

@test "doctor reads use_cursor for module gating" {
  grep -q 'DOTFILES_USE_CURSOR' "$REPO/bin/dotfiles-doctor"
  grep -q 'dig "use_cursor" true' "$REPO/bin/dotfiles-doctor"
}

@test "run_after_cursor-* scripts exit early without touching HOME when use_cursor=false" {
  local f count=0
  for f in "$REPO"/.chezmoiscripts/run_after_cursor-*.sh; do
    count=$((count + 1))
    run env HOME="$TEST_HOME" DOTFILES_USE_CURSOR=false bash "$f"
    [ "$status" -eq 0 ] || { echo "$f exited $status: $output"; return 1; }
    [[ "$output" == *"use_cursor=false"* ]] || { echo "$f did not report the skip: $output"; return 1; }
  done
  [ "$count" -ge 4 ]
  [ ! -e "$TEST_HOME/.cursor" ]
  [ ! -e "$TEST_HOME/.config/dotfiles/hooks" ]
}

@test "launchagents script re-runs when use_cursor changes" {
  run _render_launchagents false
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | sed -n 1,6p | grep -q 'use_cursor: false'
}

@test "launchagents skip Cursor-only agents when use_cursor=false" {
  _load_launchagent_helpers "$(_render_launchagents false)"
  should_skip_agent cursor-at-login
  should_skip_agent heal-stuck-agents
  ! should_skip_agent dotfiles-sync
}

@test "launchagents unload and remove installed Cursor-only agents when use_cursor=false" {
  _load_launchagent_helpers "$(_render_launchagents false)"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$TEST_DIR/bin"
  : > "$TEST_HOME/Library/LaunchAgents/com.dotfiles.cursor-at-login.plist"
  : > "$TEST_HOME/Library/LaunchAgents/com.dotfiles.dotfiles-sync.plist"
  printf '#!/bin/bash\necho "$*" >> "%s/launchctl.log"\n' "$TEST_DIR" > "$TEST_DIR/bin/launchctl"
  chmod +x "$TEST_DIR/bin/launchctl"

  should_skip_agent cursor-at-login
  HOME="$TEST_HOME" PATH="$TEST_DIR/bin:$PATH" remove_skipped_agent cursor-at-login com.dotfiles.cursor-at-login.plist
  ! should_skip_agent dotfiles-sync

  [ ! -e "$TEST_HOME/Library/LaunchAgents/com.dotfiles.cursor-at-login.plist" ]
  [ -e "$TEST_HOME/Library/LaunchAgents/com.dotfiles.dotfiles-sync.plist" ]
  grep -q "unload $TEST_HOME/Library/LaunchAgents/com.dotfiles.cursor-at-login.plist" "$TEST_DIR/launchctl.log"
}

@test "remove_skipped_agent reports nothing to remove when the agent is not installed" {
  _load_launchagent_helpers "$(_render_launchagents false)"
  mkdir -p "$TEST_HOME/Library/LaunchAgents"

  ! HOME="$TEST_HOME" remove_skipped_agent cursor-at-login com.dotfiles.cursor-at-login.plist
}

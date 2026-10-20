#!/usr/bin/env bats
# use_cursor (chezmoi data; prompt default false, missing key reads as true) turns every dotfiles-managed Cursor
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

@test "chezmoi config template declares use_cursor with default false" {
  grep -q 'promptBoolOnce . "use_cursor" ".*" false' "$REPO/.chezmoi.yaml.tmpl"
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

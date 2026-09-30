#!/usr/bin/env bats
# Tests for lib/agentbrew-locate.sh — the layout probe used by
# .chezmoiscripts/run_after_agentbrew-sync.sh and the agentbrew doctor module.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"

  # Isolate from the operator's chezmoi env (~/.config/dotfiles/env.sh exports
  # DOTFILES_REPOS_DIR at every shell startup, which would otherwise short-circuit
  # the HOME-relative probe to the real ~/apps directory).
  unset DOTFILES_REPOS_DIR

  # shellcheck source=../lib/agentbrew-locate.sh
  source "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "agentbrew_locate: prefers ~/apps/agentbrew when present alone" {
  mkdir -p "$HOME/apps/agentbrew"
  run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/apps/agentbrew" ]
}

@test "agentbrew_locate: falls back to ~/apps/tooling/agentbrew" {
  mkdir -p "$HOME/apps/tooling/agentbrew"
  run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/apps/tooling/agentbrew" ]
}

@test "agentbrew_locate: prefers current tooling checkout over historical checkout" {
  mkdir -p "$HOME/apps/agentbrew" "$HOME/apps/tooling/agentbrew"
  run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/apps/tooling/agentbrew" ]
}

@test "agentbrew_locate: returns 1 + empty when neither layout exists" {
  run agentbrew_locate
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "agentbrew_locate: honours DOTFILES_REPOS_DIR" {
  local custom="$TEST_DIR/custom-repos"
  mkdir -p "$custom/agentbrew"
  DOTFILES_REPOS_DIR="$custom" run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$custom/agentbrew" ]
}

@test "agentbrew_locate: DOTFILES_REPOS_DIR also resolves the tooling/ subpath" {
  local custom="$TEST_DIR/custom-repos"
  mkdir -p "$custom/tooling/agentbrew"
  DOTFILES_REPOS_DIR="$custom" run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$custom/tooling/agentbrew" ]
}

@test "agentbrew_locate: falls back to ~/apps when DOTFILES_REPOS_DIR misses agentbrew" {
  mkdir -p "$HOME/apps/tooling/agentbrew"
  DOTFILES_REPOS_DIR="$TEST_DIR/stale-repos" run agentbrew_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/apps/tooling/agentbrew" ]
}

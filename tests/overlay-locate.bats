#!/usr/bin/env bats
# Regression tests for auto-discovering additive dotfiles overlays.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_BASE="$TEST_DIR/dotfiles"
  TEST_REPOS="$TEST_HOME/apps/tooling"
  TEST_APPLIED="$TEST_REPOS/dotfiles-applied"
  TEST_OVERLAY="$TEST_REPOS/dotfiles-acme"

  mkdir -p "$TEST_HOME" "$TEST_BASE" "$TEST_APPLIED" "$TEST_OVERLAY"
  printf 'mcp: []\n' > "$TEST_APPLIED/Agentfile.yaml"
  printf 'mcp: []\n' > "$TEST_OVERLAY/Agentfile.yaml"

  git -C "$TEST_BASE" init -q
  git -C "$TEST_BASE" remote add origin git@example.test:dotfiles.git
  git -C "$TEST_APPLIED" init -q
  git -C "$TEST_APPLIED" remote add origin git@example.test:dotfiles.git
  git -C "$TEST_OVERLAY" init -q
  git -C "$TEST_OVERLAY" remote add origin git@example.test:dotfiles-acme.git

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_BASE"
  export DOTFILES_REPOS_DIR="$TEST_HOME/apps"
  unset EXTRA_OVERLAY_ROOT

  # Keep the test on auto-discovery instead of machine-specific chezmoi data.
  chezmoi() { return 1; }
  export -f chezmoi

  source "$BATS_TEST_DIRNAME/../lib/overlay-locate.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "auto-discovery skips a deployed checkout of the base repository" {
  [ "$(overlay_locate)" = "$TEST_OVERLAY" ]
}

@test "an explicit overlay path takes precedence over source-replica filtering" {
  EXTRA_OVERLAY_ROOT="$TEST_APPLIED"
  [ "$(overlay_locate)" = "$TEST_APPLIED" ]
}

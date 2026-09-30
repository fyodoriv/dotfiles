#!/usr/bin/env bats
# Tests for new-project scaffolding script

load test_helper

NEW_PROJECT_CMD="$BATS_TEST_DIRNAME/../bin/new-project"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME/apps"
  export HOME="$TEST_HOME"
  # Unset DOTFILES_REPOS_DIR so the script falls back to $HOME/apps
  # (= $TEST_HOME/apps). Otherwise the parent env's repos dir leaks in
  # and tests interact with real app directories.
  unset DOTFILES_REPOS_DIR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "new-project script exists and is executable" {
  [ -f "$NEW_PROJECT_CMD" ]
  [ -x "$NEW_PROJECT_CMD" ]
}

@test "new-project script has correct shebang" {
  head -1 "$NEW_PROJECT_CMD" | grep -q '#!/bin/bash'
}

@test "new-project script uses strict mode" {
  grep -q 'set -euo pipefail' "$NEW_PROJECT_CMD"
}

@test "new-project with no args shows usage and exits 1" {
  run "$NEW_PROJECT_CMD"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Usage: new-project"
}

@test "new-project with template but no name shows usage" {
  run "$NEW_PROJECT_CMD" react
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Usage: new-project"
}

@test "new-project lists available templates in usage" {
  run "$NEW_PROJECT_CMD"
  echo "$output" | grep -q "react"
  echo "$output" | grep -q "node"
  echo "$output" | grep -q "lib"
  echo "$output" | grep -q "python"
}

@test "new-project with unknown template errors" {
  run "$NEW_PROJECT_CMD" unknown test-app
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "Unknown template"
}

@test "new-project refuses to overwrite existing directory" {
  mkdir -p "$HOME/apps/existing-app"
  run "$NEW_PROJECT_CMD" node existing-app
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "already exists"
}

@test "new-project creates directory under DOTFILES_REPOS_DIR" {
  grep -q 'DOTFILES_REPOS_DIR:-\$HOME/apps' "$NEW_PROJECT_CMD"
  grep -q 'dir="\$REPOS_DIR/\$name"' "$NEW_PROJECT_CMD"
}

@test "new-project node template creates package.json and tsconfig.json" {
  grep -q 'package.json' "$NEW_PROJECT_CMD"
  grep -q 'tsconfig.json' "$NEW_PROJECT_CMD"
}

@test "new-project python template creates pyproject.toml" {
  grep -q 'pyproject.toml' "$NEW_PROJECT_CMD"
}

@test "new-project lib template configures tsup" {
  grep -q 'tsup.config.ts' "$NEW_PROJECT_CMD"
}

@test "new-project initializes git in every template" {
  grep -q 'init_git' "$NEW_PROJECT_CMD"
}

@test "new-project sets up prettier in JS templates" {
  grep -q 'init_prettier' "$NEW_PROJECT_CMD"
}

@test "new-project sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$NEW_PROJECT_CMD"
}

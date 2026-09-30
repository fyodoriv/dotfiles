#!/usr/bin/env bats
# Tests for dotfiles-profile — show or switch chezmoi profile

load test_helper

PROFILE_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-profile"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-profile script exists and is executable" {
  [ -x "$PROFILE_CMD" ]
}

@test "dotfiles-profile has correct shebang" {
  head -1 "$PROFILE_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-profile uses strict mode" {
  grep -q 'set -euo pipefail' "$PROFILE_CMD"
}

@test "dotfiles-profile --help shows usage" {
  run "$PROFILE_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"profile"* ]]
}

@test "dotfiles-profile with no args reports missing config" {
  run "$PROFILE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No chezmoi config found"* ]]
}

@test "dotfiles-profile with no args shows current profile when config exists" {
  mkdir -p "$HOME/.config/chezmoi"
  cat > "$HOME/.config/chezmoi/chezmoi.yaml" <<'EOF'
data:
  profile: full
EOF
  run "$PROFILE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Current profile: full"* ]]
}

@test "dotfiles-profile rejects invalid profile name" {
  run "$PROFILE_CMD" bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be 'core' or 'full'"* ]]
}

@test "dotfiles-profile rejects empty-string-like invalid names" {
  run "$PROFILE_CMD" minimal
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be 'core' or 'full'"* ]]
}

@test "dotfiles-profile accepts core as valid profile" {
  grep -q "core|full" "$PROFILE_CMD"
}

@test "dotfiles-profile accepts full as valid profile" {
  grep -q "core|full" "$PROFILE_CMD"
}

@test "dotfiles-profile errors when config file is missing for set" {
  run "$PROFILE_CMD" core
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "dotfiles-profile reads config from chezmoi.yaml" {
  grep -q 'chezmoi.yaml' "$PROFILE_CMD"
}

@test "dotfiles-profile uses yq to read profile" {
  grep -q 'yq' "$PROFILE_CMD"
}

@test "dotfiles-profile errors when yq is not installed" {
  # Use a minimal PATH that excludes yq
  run env PATH="/usr/bin:/bin" HOME="$TEST_HOME" bash "$PROFILE_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"yq not found"* ]]
  [[ "$output" == *"brew install yq"* ]]
}

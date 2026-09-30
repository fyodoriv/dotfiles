#!/usr/bin/env bats
# Tests for dotfiles-new-module — create a new doctor module

load test_helper

NEW_MODULE_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-new-module"

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$FAKE_DOTFILES/bin" "$FAKE_DOTFILES/modules"
  cp "$NEW_MODULE_CMD" "$FAKE_DOTFILES/bin/dotfiles-new-module"
  chmod +x "$FAKE_DOTFILES/bin/dotfiles-new-module"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- Basics ---

@test "dotfiles-new-module script exists and is executable" {
  [ -x "$NEW_MODULE_CMD" ]
}

@test "dotfiles-new-module has correct shebang" {
  head -1 "$NEW_MODULE_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-new-module uses strict mode" {
  grep -q 'set -euo pipefail' "$NEW_MODULE_CMD"
}

# --- Help and Usage ---

@test "new-module --help shows usage and exits 0" {
  run "$NEW_MODULE_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"new-module"* ]]
}

@test "new-module with no args exits 1 and shows usage" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# --- Happy Path ---

@test "new-module creates module directory" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  [ -d "$FAKE_DOTFILES/modules/testmod" ]
}

@test "new-module creates doctor.sh" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  [ -f "$FAKE_DOTFILES/modules/testmod/doctor.sh" ]
}

@test "new-module creates severity file with default cosmetic" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOTFILES/modules/testmod/severity")" = "cosmetic" ]
}

@test "new-module shows success message" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created module 'testmod'"* ]]
  [[ "$output" == *"modules/testmod/"* ]]
  [[ "$output" == *"doctor.sh"* ]]
}

# --- Severity Flag ---

@test "new-module --severity critical sets severity" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod --severity critical
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOTFILES/modules/testmod/severity")" = "critical" ]
}

@test "new-module --severity important sets severity" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod --severity important
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOTFILES/modules/testmod/severity")" = "important" ]
}

@test "new-module --severity before name works" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" --severity performance testmod
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOTFILES/modules/testmod/severity")" = "performance" ]
}

# --- Template Content ---

@test "new-module doctor.sh has correct shebang" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  head -1 "$FAKE_DOTFILES/modules/testmod/doctor.sh" | grep -q '#!/bin/bash'
}

@test "new-module doctor.sh includes module name in comment" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  grep -q 'testmod' "$FAKE_DOTFILES/modules/testmod/doctor.sh"
}

@test "new-module doctor.sh includes check example" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  grep -q 'check ' "$FAKE_DOTFILES/modules/testmod/doctor.sh"
}

@test "new-module doctor.sh includes check_symlink example" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  grep -q 'check_symlink' "$FAKE_DOTFILES/modules/testmod/doctor.sh"
}

@test "new-module doctor.sh includes check_defaults example" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  grep -q 'check_defaults' "$FAKE_DOTFILES/modules/testmod/doctor.sh"
}

# --- Error Cases ---

@test "new-module rejects existing module" {
  mkdir -p "$FAKE_DOTFILES/modules/existing"
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" existing
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "new-module handles hyphenated names" {
  run "$FAKE_DOTFILES/bin/dotfiles-new-module" my-test-module
  [ "$status" -eq 0 ]
  [ -d "$FAKE_DOTFILES/modules/my-test-module" ]
  grep -q 'my-test-module' "$FAKE_DOTFILES/modules/my-test-module/doctor.sh"
}

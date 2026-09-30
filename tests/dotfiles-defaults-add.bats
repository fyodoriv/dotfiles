#!/usr/bin/env bats
# Tests for dotfiles-defaults-add — add a macOS defaults setting to JSON + doctor check

load test_helper

DEFAULTS_ADD_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-defaults-add"

setup() {
  TEST_DIR="$(mktemp -d)"
  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$FAKE_DOTFILES/bin" "$FAKE_DOTFILES/modules/macos" "$FAKE_DOTFILES/data"
  echo "[]" > "$FAKE_DOTFILES/data/macos-defaults.json"
  echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/macos/doctor.sh"
  cp "$DEFAULTS_ADD_CMD" "$FAKE_DOTFILES/bin/dotfiles-defaults-add"
  chmod +x "$FAKE_DOTFILES/bin/dotfiles-defaults-add"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# --- Basics ---

@test "dotfiles-defaults-add script exists and is executable" {
  [ -x "$DEFAULTS_ADD_CMD" ]
}

@test "dotfiles-defaults-add has correct shebang" {
  head -1 "$DEFAULTS_ADD_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-defaults-add uses strict mode" {
  grep -q 'set -euo pipefail' "$DEFAULTS_ADD_CMD"
}

# --- Help and Usage ---

@test "defaults-add --help shows usage and exits 0" {
  run "$DEFAULTS_ADD_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaults-add"* ]]
}

@test "defaults-add with no args exits 1 and shows usage" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "defaults-add with 3 args exits 1" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

# --- Happy Path ---

@test "defaults-add appends entry to JSON data file" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "com.apple.dock" and .key == "autohide" and .value == true)' "$FAKE_DOTFILES/data/macos-defaults.json"
}

@test "defaults-add appends check_defaults to doctor.sh" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  grep -q 'check_defaults "macos.autohide"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

@test "defaults-add shows success message" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added default"* ]]
  [[ "$output" == *"Data:"* ]]
  [[ "$output" == *"Doctor: modules/macos/doctor.sh"* ]]
}

# --- Type Handling ---

@test "defaults-add handles int type" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" NSGlobalDomain KeyRepeat 1 int
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "NSGlobalDomain" and .key == "KeyRepeat" and .value == 1 and .type == "int")' "$FAKE_DOTFILES/data/macos-defaults.json"
}

@test "defaults-add handles float type" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide-delay 0.12 float
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "com.apple.dock" and .key == "autohide-delay" and .value == 0.12)' "$FAKE_DOTFILES/data/macos-defaults.json"
}

@test "defaults-add handles string type" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.screencapture type png string
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "com.apple.screencapture" and .key == "type" and .value == "png")' "$FAKE_DOTFILES/data/macos-defaults.json"
}

# --- Module Flag ---

@test "defaults-add respects --module flag" {
  mkdir -p "$FAKE_DOTFILES/modules/custom"
  echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/custom/doctor.sh"
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.example foo bar string --module custom
  [ "$status" -eq 0 ]
  grep -q 'check_defaults "custom.foo"' "$FAKE_DOTFILES/modules/custom/doctor.sh"
  ! grep -q 'custom' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

@test "defaults-add defaults to macos module" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.example test value bool
  [ "$status" -eq 0 ]
  grep -q 'check_defaults "macos.test"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

# --- Script Flag ---

@test "defaults-add respects --script flag" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock tilesize 44 int --script visual
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.script == "visual")' "$FAKE_DOTFILES/data/macos-defaults.json"
}

@test "defaults-add defaults to core script" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.example test value bool
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.script == "core")' "$FAKE_DOTFILES/data/macos-defaults.json"
}

# --- Check ID Sanitization ---

@test "defaults-add sanitizes hyphens in check_id" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide-delay 0 float
  [ "$status" -eq 0 ]
  grep -q 'check_defaults "macos.autohide_delay"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

@test "defaults-add sanitizes dots in check_id" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.Safari com.apple.key true bool
  [ "$status" -eq 0 ]
  grep -q 'check_defaults "macos.com_apple_key"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

# --- Description and Content ---

@test "defaults-add generates correct description" {
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  grep -q '"autohide = true"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

@test "defaults-add preserves existing JSON entries" {
  echo '[{"domain":"existing","key":"entry","type":"bool","value":true,"section":"Test","script":"core"}]' > "$FAKE_DOTFILES/data/macos-defaults.json"
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "existing")' "$FAKE_DOTFILES/data/macos-defaults.json"
  jq -e '.[] | select(.domain == "com.apple.dock")' "$FAKE_DOTFILES/data/macos-defaults.json"
}

@test "defaults-add preserves existing doctor.sh content" {
  echo '# Existing check' >> "$FAKE_DOTFILES/modules/macos/doctor.sh"
  run "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  grep -q '# Existing check' "$FAKE_DOTFILES/modules/macos/doctor.sh"
  grep -q 'check_defaults "macos.autohide"' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

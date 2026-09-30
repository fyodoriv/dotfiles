#!/usr/bin/env bats
# Tests for lib/colors.sh — ANSI color variables and logging helpers

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  COLORS_LIB="$BATS_TEST_DIRNAME/../lib/colors.sh"
  # bats stdout is not a TTY; force colors on for existing tests
  export FORCE_COLOR=1
  unset NO_COLOR
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "colors.sh exists and is sourceable" {
  [ -f "$COLORS_LIB" ]
  source "$COLORS_LIB"
}

@test "GREEN is defined and contains escape sequence" {
  source "$COLORS_LIB"
  [ -n "$GREEN" ]
  [[ "$GREEN" == *"\\033["* ]] || [[ "$GREEN" == *$'\033['* ]]
}

@test "RED is defined and contains escape sequence" {
  source "$COLORS_LIB"
  [ -n "$RED" ]
  [[ "$RED" == *"\\033["* ]] || [[ "$RED" == *$'\033['* ]]
}

@test "YELLOW is defined and contains escape sequence" {
  source "$COLORS_LIB"
  [ -n "$YELLOW" ]
  [[ "$YELLOW" == *"\\033["* ]] || [[ "$YELLOW" == *$'\033['* ]]
}

@test "BLUE is defined and contains escape sequence" {
  source "$COLORS_LIB"
  [ -n "$BLUE" ]
  [[ "$BLUE" == *"\\033["* ]] || [[ "$BLUE" == *$'\033['* ]]
}

@test "DIM is defined and contains escape sequence" {
  source "$COLORS_LIB"
  [ -n "$DIM" ]
  [[ "$DIM" == *"\\033["* ]] || [[ "$DIM" == *$'\033['* ]]
}

@test "NC (no color) is defined and resets formatting" {
  source "$COLORS_LIB"
  [ -n "$NC" ]
  [[ "$NC" == *"\\033[0m"* ]] || [[ "$NC" == *$'\033[0m'* ]]
}

@test "info() produces output containing the message" {
  source "$COLORS_LIB"
  run info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "ok() produces output containing the message" {
  source "$COLORS_LIB"
  run ok "success message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"success message"* ]]
}

@test "warn() produces output containing the message" {
  source "$COLORS_LIB"
  run warn "warning message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warning message"* ]]
}

@test "fail() produces output containing the message" {
  source "$COLORS_LIB"
  run fail "error message"
  [ "$status" -eq 0 ]
  [[ "$output" == *"error message"* ]]
}

@test "section() produces output containing the section name" {
  source "$COLORS_LIB"
  run section "My Section"
  [ "$status" -eq 0 ]
  [[ "$output" == *"My Section"* ]]
}

@test "notify() runs without error" {
  source "$COLORS_LIB"
  # Just verify it doesn't crash — notification delivery is best-effort
  run notify "Test Title" "Test Message"
  [ "$status" -eq 0 ]
}

@test "all six color variables are distinct" {
  source "$COLORS_LIB"
  [ "$GREEN" != "$RED" ]
  [ "$GREEN" != "$YELLOW" ]
  [ "$GREEN" != "$BLUE" ]
  [ "$RED" != "$YELLOW" ]
  [ "$RED" != "$BLUE" ]
  [ "$YELLOW" != "$BLUE" ]
}

# ── NO_COLOR support (https://no-color.org/) ──

@test "NO_COLOR=1 disables all color variables" {
  export NO_COLOR=1
  unset FORCE_COLOR
  source "$COLORS_LIB"
  [ -z "$GREEN" ]
  [ -z "$RED" ]
  [ -z "$YELLOW" ]
  [ -z "$BLUE" ]
  [ -z "$DIM" ]
  [ -z "$NC" ]
}

@test "NO_COLOR= (empty) still disables colors" {
  export NO_COLOR=
  unset FORCE_COLOR
  source "$COLORS_LIB"
  [ -z "$GREEN" ]
  [ -z "$RED" ]
}

@test "NO_COLOR logging helpers still produce messages" {
  export NO_COLOR=1
  unset FORCE_COLOR
  source "$COLORS_LIB"
  run info "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
  run ok "success"
  [[ "$output" == *"success"* ]]
}

@test "non-TTY stdout disables colors without FORCE_COLOR" {
  unset FORCE_COLOR NO_COLOR
  # Pipe through cat to ensure stdout is not a TTY
  run bash -c 'source "'"$COLORS_LIB"'" && echo "GREEN=$GREEN"'
  [[ "$output" == "GREEN=" ]]
}

@test "FORCE_COLOR=1 overrides non-TTY detection" {
  export FORCE_COLOR=1
  unset NO_COLOR
  source "$COLORS_LIB"
  [ -n "$GREEN" ]
  [[ "$GREEN" == *"\\033["* ]] || [[ "$GREEN" == *$'\033['* ]]
}

@test "NO_COLOR takes precedence over FORCE_COLOR" {
  export NO_COLOR=1
  export FORCE_COLOR=1
  source "$COLORS_LIB"
  [ -z "$GREEN" ]
  [ -z "$RED" ]
}

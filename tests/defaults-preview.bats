#!/usr/bin/env bats
# Tests for dotfiles-defaults-preview

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

# Each bare `dotfiles-defaults-preview` invocation scans 100+ macOS
# defaults, which costs ~5s. Five of the tests check different
# substrings of the same output — run it ONCE per file and cache.
setup_file() {
  export DP_CACHE_DIR="$(mktemp -d)"
  export DP_OUT="$DP_CACHE_DIR/out"
  export DP_STATUS="$DP_CACHE_DIR/status"
  bash "$DOTFILES_DIR/bin/dotfiles-defaults-preview" > "$DP_OUT" 2>&1
  echo "$?" > "$DP_STATUS"
}

teardown_file() {
  rm -rf "$DP_CACHE_DIR"
}

load_cached() {
  output="$(cat "$DP_OUT")"
  status="$(cat "$DP_STATUS")"
}

@test "defaults-preview exits 0" {
  load_cached
  [ "$status" -eq 0 ]
}

@test "defaults-preview prints summary with total reviewed" {
  load_cached
  [[ "$output" == *"total reviewed"* ]]
}

@test "defaults-preview shows all three script categories" {
  load_cached
  [[ "$output" == *"macos.sh"* ]]
  [[ "$output" == *"macos-visual.sh"* ]]
  [[ "$output" == *"macos-apps.sh"* ]]
}

@test "defaults-preview --changed exits 0" {
  run bash "$DOTFILES_DIR/bin/dotfiles-defaults-preview" --changed
  [ "$status" -eq 0 ]
}

@test "defaults-preview shows no-write disclaimer" {
  load_cached
  [[ "$output" == *"no changes were made"* ]]
}

@test "defaults-preview reviews at least 100 settings" {
  load_cached
  # Extract total count from summary line
  [[ "$output" =~ ([0-9]+)\ total\ reviewed ]]
  total="${BASH_REMATCH[1]}"
  [ "$total" -ge 100 ]
}

@test "defaults-preview --help exits 0 and shows usage" {
  run bash "$DOTFILES_DIR/bin/dotfiles-defaults-preview" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaults-preview"* ]]
}

@test "dotfiles defaults-preview dispatches correctly" {
  run bash "$DOTFILES_DIR/bin/dotfiles" defaults-preview --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"defaults-preview"* ]]
}

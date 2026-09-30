#!/usr/bin/env bats
# Tests for dotfiles-quickstart interactive wizard

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

@test "quickstart --help exits 0 and shows usage" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-quickstart"* ]]
}

@test "quickstart --check exits 0 when prerequisites are met" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Prerequisites"* ]]
}

@test "quickstart --check verifies Xcode CLT" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --check
  [[ "$output" == *"Xcode"* ]]
}

@test "quickstart --check verifies Homebrew" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --check
  [[ "$output" == *"Homebrew"* ]]
}

@test "quickstart --check verifies chezmoi" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --check
  [[ "$output" == *"chezmoi"* ]]
}

@test "quickstart --check verifies Git" {
  run bash "$DOTFILES_DIR/bin/dotfiles-quickstart" --check
  [[ "$output" == *"Git"* ]]
}

@test "quickstart has set -euo pipefail" {
  grep -q 'set -euo pipefail' "$DOTFILES_DIR/bin/dotfiles-quickstart"
}

@test "dotfiles quickstart dispatches correctly" {
  run bash "$DOTFILES_DIR/bin/dotfiles" quickstart --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-quickstart"* ]]
}

#!/usr/bin/env bats
# Tests for lib/dotfiles-arch.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  # shellcheck source=../lib/dotfiles-arch.sh
  source "$DOTFILES_DIR/lib/dotfiles-arch.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "dotfiles-arch: dotfiles_brew_prefix honors DOTFILES_BREW_PREFIX" {
  export DOTFILES_BREW_PREFIX="/tmp/custom-brew"
  [ "$(dotfiles_brew_prefix)" = "/tmp/custom-brew" ]
  unset DOTFILES_BREW_PREFIX
}

@test "dotfiles-arch: macos-apps.sh clears managed app Rosetta overrides on Apple Silicon" {
  grep -q 'dotfiles_clear_managed_app_rosetta_overrides' "$DOTFILES_DIR/macos-apps.sh"
  ! grep -q 'LSArchitecturePriority -array x86_64' "$DOTFILES_DIR/macos-apps.sh"
}

@test "dotfiles-arch: macos-apps.sh sources dotfiles-arch helpers" {
  grep -q 'source "$DOTFILES_DIR/lib/dotfiles-arch.sh"' "$DOTFILES_DIR/macos-apps.sh"
}

@test "dotfiles-arch: managed app list includes Ghostty and no Cursor" {
  ! grep -q 'Cursor:' "$DOTFILES_DIR/lib/dotfiles-arch.sh"
  grep -q 'Ghostty:com.mitchellh.ghostty' "$DOTFILES_DIR/lib/dotfiles-arch.sh"
}

@test "dotfiles-arch: terminal doctor flags managed apps x86 override on Apple Silicon" {
  grep -q 'apps.no_rosetta_override' "$DOTFILES_DIR/modules/terminal/doctor.sh"
  grep -q 'dotfiles_managed_apps_have_no_x86_override' "$DOTFILES_DIR/modules/terminal/doctor.sh"
}

@test "dotfiles-arch: terminal doctor flags Ghostty x86_64 on Apple Silicon" {
  grep -q 'dotfiles_is_apple_silicon' "$DOTFILES_DIR/modules/terminal/doctor.sh"
  grep -q 'dotfiles_app_has_x86_ls_priority' "$DOTFILES_DIR/modules/terminal/doctor.sh"
  ! grep -q 'defaults write com.mitchellh.ghostty LSArchitecturePriority -array x86_64' "$DOTFILES_DIR/modules/terminal/doctor.sh"
}

@test "dotfiles-arch: uv python setup prefers ~/.local/bin on native arm64" {
  grep -q '_py_link_dir="$HOME/.local/bin"' "$DOTFILES_DIR/.chezmoiscripts/run_after_uv-python-setup.sh"
}

@test "dotfiles-arch: security doctor checks native homebrew prefix on arm64" {
  grep -q 'security.homebrew_native_prefix' "$DOTFILES_DIR/modules/security/doctor.sh"
}

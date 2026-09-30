#!/usr/bin/env bats
# Integration tests for dotfiles-add and dotfiles-unmanage subcommands.

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME"
  export HOME="$TEST_HOME"

  # Build a minimal fake dotfiles repo with the required structure
  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$FAKE_DOTFILES/bin" "$FAKE_DOTFILES/home"
  mkdir -p "$FAKE_DOTFILES/modules/tools" "$FAKE_DOTFILES/modules/git"
  mkdir -p "$FAKE_DOTFILES/modules/ssh" "$FAKE_DOTFILES/modules/shell"

  # Seed each module's doctor.sh with a shebang so appends work
  for mod in tools git ssh shell; do
    echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/$mod/doctor.sh"
  done

  # Copy the subcommand scripts into the fake repo
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-add" "$FAKE_DOTFILES/bin/dotfiles-add"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-unmanage" "$FAKE_DOTFILES/bin/dotfiles-unmanage"
  chmod +x "$FAKE_DOTFILES/bin/dotfiles-add" "$FAKE_DOTFILES/bin/dotfiles-unmanage"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── dotfiles-add ─────────────────────────────────────────────────

@test "dotfiles-add with no args exits 1 and shows usage" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-add"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "dotfiles-add with nonexistent file exits 1" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.nonexistent"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "dotfiles-add symlink mode copies file to home/" {
  echo "my-config-content" > "$TEST_HOME/.toolrc"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.toolrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"symlink mode"* ]]
  # Source file should be copied to home/ (dot stripped)
  [ -f "$FAKE_DOTFILES/home/toolrc" ]
  [ "$(cat "$FAKE_DOTFILES/home/toolrc")" = "my-config-content" ]
}

@test "dotfiles-add symlink mode creates chezmoi symlink template" {
  echo "my-config" > "$TEST_HOME/.myrc"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.myrc"
  [ "$status" -eq 0 ]
  # Should create symlink_dot_myrc.tmpl pointing to home/myrc
  [ -f "$FAKE_DOTFILES/symlink_dot_myrc.tmpl" ]
  grep -q 'home/myrc' "$FAKE_DOTFILES/symlink_dot_myrc.tmpl"
}

@test "dotfiles-add symlink mode appends check_symlink to doctor.sh" {
  echo "my-config" > "$TEST_HOME/.myapp"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.myapp"
  [ "$status" -eq 0 ]
  grep -q 'check_symlink' "$FAKE_DOTFILES/modules/tools/doctor.sh"
  grep -q '_myapp' "$FAKE_DOTFILES/modules/tools/doctor.sh"
}

@test "dotfiles-add auto-detects git module" {
  mkdir -p "$TEST_HOME"
  echo "gitcfg" > "$TEST_HOME/.gitfoo"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.gitfoo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"module 'git'"* ]]
  grep -q 'check_symlink' "$FAKE_DOTFILES/modules/git/doctor.sh"
}

@test "dotfiles-add auto-detects ssh module" {
  mkdir -p "$TEST_HOME/.ssh"
  echo "ssh-stuff" > "$TEST_HOME/.ssh/mykey_config"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.ssh/mykey_config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"module 'ssh'"* ]]
}

@test "dotfiles-add auto-detects shell module" {
  echo "zsh-stuff" > "$TEST_HOME/.zshenv_custom"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.zshenv_custom"
  [ "$status" -eq 0 ]
  [[ "$output" == *"module 'shell'"* ]]
}

@test "dotfiles-add respects explicit --module flag" {
  echo "explicit" > "$TEST_HOME/.somefile"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.somefile" --module git
  [ "$status" -eq 0 ]
  [[ "$output" == *"module 'git'"* ]]
  grep -q 'check_symlink' "$FAKE_DOTFILES/modules/git/doctor.sh"
}

@test "dotfiles-add fails for nonexistent module" {
  echo "test" > "$TEST_HOME/.testfile"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.testfile" --module nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"module 'nonexistent' not found"* ]]
}

@test "dotfiles-add shows next step" {
  echo "content" > "$TEST_HOME/.foorc"
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.foorc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Next: dotfiles apply"* ]]
}

# ── dotfiles-unmanage ────────────────────────────────────────────

@test "dotfiles-unmanage with no args exits 1 and shows usage" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "dotfiles-unmanage for unmanaged file exits 1" {
  echo "unmanaged" > "$TEST_HOME/.random"
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage" "$TEST_HOME/.random"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not appear to be managed"* ]]
}

@test "dotfiles-unmanage removes symlink source from home/" {
  # Simulate a previously-added symlink-mode file
  echo "content" > "$FAKE_DOTFILES/home/bazrc"
  echo "content" > "$TEST_HOME/.bazrc"
  echo 'check_symlink "symlink._bazrc" "$DOTFILES_DIR/home/bazrc" "$HOME/.bazrc"' >> "$FAKE_DOTFILES/modules/tools/doctor.sh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage" "$TEST_HOME/.bazrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed symlink source"* ]]
  [ ! -f "$FAKE_DOTFILES/home/bazrc" ]
}

@test "dotfiles-unmanage removes doctor check lines" {
  # Simulate a previously-added file with doctor check
  echo "content" > "$FAKE_DOTFILES/home/barrc"
  echo "content" > "$TEST_HOME/.barrc"
  echo 'check_symlink "symlink._barrc" "$DOTFILES_DIR/home/barrc" "$HOME/.barrc"' >> "$FAKE_DOTFILES/modules/tools/doctor.sh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage" "$TEST_HOME/.barrc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed doctor check"* ]]
  ! grep -q '_barrc' "$FAKE_DOTFILES/modules/tools/doctor.sh"
}

@test "dotfiles-unmanage leaves target file in place" {
  echo "keep-me" > "$FAKE_DOTFILES/home/keeprc"
  echo "keep-me" > "$TEST_HOME/.keeprc"
  echo 'check_symlink "symlink._keeprc" "$DOTFILES_DIR/home/keeprc" "$HOME/.keeprc"' >> "$FAKE_DOTFILES/modules/tools/doctor.sh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage" "$TEST_HOME/.keeprc"
  [ "$status" -eq 0 ]
  [[ "$output" == *"File left in place"* ]]
  [ -f "$TEST_HOME/.keeprc" ]
  [ "$(cat "$TEST_HOME/.keeprc")" = "keep-me" ]
}

# ── Round-trip: add then unmanage ────────────────────────────────

@test "add then unmanage round-trip cleans up completely" {
  echo "round-trip" > "$TEST_HOME/.triprc"

  # Add
  run bash "$FAKE_DOTFILES/bin/dotfiles-add" "$TEST_HOME/.triprc"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_DOTFILES/home/triprc" ]
  grep -q '_triprc' "$FAKE_DOTFILES/modules/tools/doctor.sh"

  # Unmanage
  run bash "$FAKE_DOTFILES/bin/dotfiles-unmanage" "$TEST_HOME/.triprc"
  [ "$status" -eq 0 ]
  [ ! -f "$FAKE_DOTFILES/home/triprc" ]
  ! grep -q '_triprc' "$FAKE_DOTFILES/modules/tools/doctor.sh"

  # Target file still exists
  [ -f "$TEST_HOME/.triprc" ]
}

# ── Module name validation ───────────────────────────────────────

@test "add rejects traversal module name (../etc)" {
  echo "test" > "$TEST_HOME/.testfile"
  run "$FAKE_DOTFILES/bin/dotfiles-add" --module "../etc" "$TEST_HOME/.testfile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid module name"* ]]
}

@test "add rejects module name with slash" {
  echo "test" > "$TEST_HOME/.testfile"
  run "$FAKE_DOTFILES/bin/dotfiles-add" --module "foo/bar" "$TEST_HOME/.testfile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid module name"* ]]
}

@test "add rejects module name with spaces" {
  echo "test" > "$TEST_HOME/.testfile"
  run "$FAKE_DOTFILES/bin/dotfiles-add" --module "foo bar" "$TEST_HOME/.testfile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid module name"* ]]
}

@test "add accepts valid module name with hyphen" {
  mkdir -p "$FAKE_DOTFILES/modules/my-mod"
  echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/my-mod/doctor.sh"
  echo "test" > "$TEST_HOME/.testfile"
  run "$FAKE_DOTFILES/bin/dotfiles-add" --module "my-mod" "$TEST_HOME/.testfile"
  [ "$status" -eq 0 ]
}

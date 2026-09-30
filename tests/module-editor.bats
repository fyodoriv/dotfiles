#!/usr/bin/env bats
# Functional tests for modules/editor/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  # dot_editorconfig and dot_npmrc are files, created below

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Doctor framework state
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check_managed() {
    local id="$1" src="$2" dst="$3"
    local desc="$dst → dotfiles"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$desc (symlink)"
    elif [ -f "$dst" ] && [ -f "$src" ] && diff -q "$dst" "$src" >/dev/null 2>&1; then
      pass "$desc (managed)"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

  # Create source files. `.npmrc` is rendered by a modify_ script rather than
  # copied, because npm writes registry credentials into the target file and a
  # plain managed file would delete them on every apply.
  echo "root = true" > "$TEST_DOTFILES/dot_editorconfig"
  echo "save-exact=true" > "$TEST_DOTFILES/modify_private_dot_npmrc"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "editor: passes when editorconfig matches source" {
  cp "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "editor: fails when editorconfig is missing" {
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "editor: fix mode creates missing editorconfig" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$fix_count" -ge 1 ]
  [ -f "$TEST_HOME/.editorconfig" ]
}

@test "editor: passes when both editorconfig and npmrc match source" {
  cp "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  cp "$TEST_DOTFILES/modify_private_dot_npmrc" "$TEST_HOME/.npmrc"
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$pass_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

@test "editor: fails when npmrc content differs" {
  echo "wrong content" > "$TEST_HOME/.npmrc"
  cp "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "editor: skips overridden checks" {
  echo "managed.editorconfig" >> "$OVERRIDES_FILE"
  echo "managed.npmrc" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$skip_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

@test "editor: passes with symlinked editorconfig" {
  ln -s "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  source "$BATS_TEST_DIRNAME/../modules/editor/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

#!/usr/bin/env bats
# Functional tests for modules/extras/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.gradle"
  mkdir -p "$TEST_HOME/.config/lazygit"
  mkdir -p "$TEST_DOTFILES/dot_gradle"
  mkdir -p "$TEST_DOTFILES/dot_config/lazygit"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

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

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

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

  # Create source files
  echo "org.gradle.jvmargs=-Xmx4g" > "$TEST_DOTFILES/dot_gradle/gradle.properties"
  echo "gui: {}" > "$TEST_DOTFILES/dot_config/lazygit/config.yml"
  echo "set main-view = date:default" > "$TEST_DOTFILES/dot_tigrc"

  # Mock dockutil as available
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/bash' > "$TEST_DIR/bin/dockutil"
  chmod +x "$TEST_DIR/bin/dockutil"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "extras: passes when all managed files match source" {
  cp "$TEST_DOTFILES/dot_gradle/gradle.properties" "$TEST_HOME/.gradle/gradle.properties"
  cp "$TEST_DOTFILES/dot_config/lazygit/config.yml" "$TEST_HOME/.config/lazygit/config.yml"
  cp "$TEST_DOTFILES/dot_tigrc" "$TEST_HOME/.tigrc"
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  # dockutil + 3 managed files
  [ "$pass_count" -eq 4 ]
  [ "$fail_count" -eq 0 ]
}

@test "extras: fails when managed files missing" {
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  # 3 managed files should fail
  [ "$fail_count" -ge 3 ]
}

@test "extras: fix mode copies managed files" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  [ "$fix_count" -ge 3 ]
  [ -f "$TEST_HOME/.gradle/gradle.properties" ]
  [ -f "$TEST_HOME/.config/lazygit/config.yml" ]
  [ -f "$TEST_HOME/.tigrc" ]
}

@test "extras: overrides skip checks" {
  echo "managed.gradle" >> "$OVERRIDES_FILE"
  echo "managed.lazygit" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  [ "$skip_count" -ge 2 ]
}

@test "extras: dockutil missing fails only that check" {
  rm -f "$TEST_DIR/bin/dockutil"
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
  cp "$TEST_DOTFILES/dot_gradle/gradle.properties" "$TEST_HOME/.gradle/gradle.properties"
  cp "$TEST_DOTFILES/dot_config/lazygit/config.yml" "$TEST_HOME/.config/lazygit/config.yml"
  cp "$TEST_DOTFILES/dot_tigrc" "$TEST_HOME/.tigrc"
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  [ "$pass_count" -eq 3 ]
  [ "$fail_count" -eq 1 ]
}

@test "extras: managed file with different content fails" {
  cp "$TEST_DOTFILES/dot_gradle/gradle.properties" "$TEST_HOME/.gradle/gradle.properties"
  cp "$TEST_DOTFILES/dot_config/lazygit/config.yml" "$TEST_HOME/.config/lazygit/config.yml"
  echo "different content" > "$TEST_HOME/.tigrc"
  source "$BATS_TEST_DIRNAME/../modules/extras/doctor.sh"
  # tigrc should fail because content differs
  [ "$fail_count" -ge 1 ]
}

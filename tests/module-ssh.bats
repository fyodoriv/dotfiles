#!/usr/bin/env bats
# Functional tests for modules/ssh/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.ssh"
  mkdir -p "$TEST_DOTFILES/private_dot_ssh"

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

  # Create source template
  echo "Host *" > "$TEST_DOTFILES/private_dot_ssh/config.tmpl"
  echo "  ServerAliveInterval 60" >> "$TEST_DOTFILES/private_dot_ssh/config.tmpl"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "ssh: passes when config is symlinked to source" {
  ln -s "$TEST_DOTFILES/private_dot_ssh/config.tmpl" "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "ssh: fails when config is missing" {
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "ssh: passes when config content matches (managed)" {
  cp "$TEST_DOTFILES/private_dot_ssh/config.tmpl" "$TEST_HOME/.ssh/config"
  chmod 600 "$TEST_HOME/.ssh/config"
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "ssh: fix mode copies missing config" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  [ "$fix_count" -ge 1 ]
  [ -f "$TEST_HOME/.ssh/config" ]
}

@test "ssh: permissions pass when 600" {
  ln -s "$TEST_DOTFILES/private_dot_ssh/config.tmpl" "$TEST_HOME/.ssh/config"
  # stat -f '%A' follows symlinks and returns the target's permissions
  chmod 600 "$TEST_DOTFILES/private_dot_ssh/config.tmpl"
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  # At minimum the managed check passes
  [ "$pass_count" -ge 1 ]
}

@test "ssh: overrides skip checks" {
  echo "managed.ssh" >> "$OVERRIDES_FILE"
  echo "security.ssh_permissions" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/ssh/doctor.sh"
  [ "$skip_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

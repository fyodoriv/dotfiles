#!/usr/bin/env bats
# Functional tests for modules/tools/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.local/bin"
  mkdir -p "$TEST_DOTFILES"

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

  check_managed() { :; }

  # Create mock tool binaries
  mkdir -p "$TEST_DIR/bin"
  for tool in fzf eza bat fd rg zoxide tree htop jq gum delta fastfetch topgrade; do
    echo '#!/bin/bash' > "$TEST_DIR/bin/$tool"
    chmod +x "$TEST_DIR/bin/$tool"
  done
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "tools: passes when all tools installed" {
  source "$BATS_TEST_DIRNAME/../modules/tools/doctor.sh"
  [ "$pass_count" -eq 13 ]
  [ "$fail_count" -eq 0 ]
}

@test "tools: fails when tools missing" {
  rm -f "$TEST_DIR/bin/fzf" "$TEST_DIR/bin/eza" "$TEST_DIR/bin/bat"
  # Restrict PATH to prevent finding real system binaries
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/tools/doctor.sh"
  [ "$fail_count" -ge 3 ]
}

@test "tools: overrides skip specific tools" {
  echo "tool.fzf" >> "$OVERRIDES_FILE"
  echo "tool.eza" >> "$OVERRIDES_FILE"
  echo "tool.bat" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/tools/doctor.sh"
  [ "$skip_count" -ge 3 ]
}

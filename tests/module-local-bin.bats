#!/usr/bin/env bats
# Tests for modules/local-bin/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME/.local/bin" "$TEST_DOTFILES/modules/local-bin"
  cp "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh" "$TEST_DOTFILES/modules/local-bin/"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"; touch "$OVERRIDES_FILE"
  FIX_MODE=false; LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else fail "$desc"; fi
  }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "local-bin: passes when .local/bin exists and is on PATH" {
  export PATH="$TEST_HOME/.local/bin:$PATH"
  source "$TEST_DOTFILES/modules/local-bin/doctor.sh"
  [ "$pass_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

@test "local-bin: fails when .local/bin is not on PATH" {
  export PATH="/usr/bin:/bin"
  source "$TEST_DOTFILES/modules/local-bin/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "local-bin: fix mode creates .local/bin if missing" {
  FIX_MODE=true
  rmdir "$TEST_HOME/.local/bin"
  export PATH="$TEST_HOME/.local/bin:$PATH"
  source "$TEST_DOTFILES/modules/local-bin/doctor.sh"
  [ -d "$TEST_HOME/.local/bin" ]
}

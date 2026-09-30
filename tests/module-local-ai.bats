#!/usr/bin/env bats
# Tests for modules/local-ai/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/local-ai"
  cp "$BATS_TEST_DIRNAME/../modules/local-ai/doctor.sh" "$TEST_DOTFILES/modules/local-ai/"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"; touch "$OVERRIDES_FILE"
  FIX_MODE=false; LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0
  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  audit_warn() { warn_count=$((warn_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else fail "$desc"; fi
  }
  check_advisory() { check "$@"; }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "local-ai: module file exists" {
  [ -f "$TEST_DOTFILES/modules/local-ai/doctor.sh" ]
}

@test "local-ai: fails when no inference engine is installed" {
  _lmstudio_installed() { return 1; }
  _ollama_installed() { return 1; }
  source "$TEST_DOTFILES/modules/local-ai/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "local-ai: passes engine check when ollama is on PATH" {
  # Only test the engine detection logic — mock the functions
  _lmstudio_installed() { return 1; }
  _ollama_installed() { return 0; }
  _lmstudio_up() { return 1; }
  _ollama_up() { return 1; }
  ollama() { return 0; }
  export -f ollama
  source "$TEST_DOTFILES/modules/local-ai/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

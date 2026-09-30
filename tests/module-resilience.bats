#!/usr/bin/env bats
# Tests for modules/resilience/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/resilience" "$TEST_DOTFILES/bin"
  cp "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" "$TEST_DOTFILES/modules/resilience/"
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
  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    else audit_warn "$desc"; fi
  }
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return; is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else fail "$desc"; fi
  }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "resilience: module file exists" {
  [ -f "$TEST_DOTFILES/modules/resilience/doctor.sh" ]
}

@test "resilience: fails when tmux is not installed" {
  mkdir -p "$TEST_DIR/empty_bin"
  export PATH="$TEST_DIR/empty_bin:/usr/bin:/bin:/usr/sbin:/sbin"
  touch "$TEST_DOTFILES/bin/agent-tmux"
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "resilience: passes tmux check when tmux exists" {
  mkdir -p "$TEST_DIR/mock_bin"
  cat > "$TEST_DIR/mock_bin/tmux" << 'EOF'
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_DIR/mock_bin/tmux"
  export PATH="$TEST_DIR/mock_bin:$PATH"
  touch "$TEST_DOTFILES/bin/agent-tmux"
  chmod +x "$TEST_DOTFILES/bin/agent-tmux"
  source "$TEST_DOTFILES/modules/resilience/doctor.sh"
  [ "$pass_count" -ge 2 ]
}

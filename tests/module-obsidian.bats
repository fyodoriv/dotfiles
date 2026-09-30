#!/usr/bin/env bats
# Tests for modules/obsidian/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  VAULT="$TEST_HOME/notes"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/obsidian"
  cp "$BATS_TEST_DIRNAME/../modules/obsidian/doctor.sh" "$TEST_DOTFILES/modules/obsidian/"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_PROFILE="full"
  export OBSIDIAN_VAULT="$VAULT"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else
      fail "$desc"
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "obsidian: skips when profile is not full" {
  DOTFILES_PROFILE="minimal"
  source "$TEST_DOTFILES/modules/obsidian/doctor.sh"
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "obsidian: fails when vault does not exist" {
  mkdir -p "$TEST_HOME/Applications/Obsidian.app"
  source "$TEST_DOTFILES/modules/obsidian/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "obsidian: passes with full vault setup" {
  mkdir -p "$TEST_HOME/Applications/Obsidian.app"
  mkdir -p "$VAULT/.obsidian" "$VAULT/daily" "$VAULT/templates"
  echo '{"vimMode": true}' > "$VAULT/.obsidian/app.json"
  source "$TEST_DOTFILES/modules/obsidian/doctor.sh"
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -ge 4 ]
}

@test "obsidian: fix mode creates missing vault directories" {
  FIX_MODE=true
  mkdir -p "$TEST_HOME/Applications/Obsidian.app"
  mkdir -p "$VAULT/.obsidian"
  echo '{"vimMode": true}' > "$VAULT/.obsidian/app.json"
  source "$TEST_DOTFILES/modules/obsidian/doctor.sh"
  [ -d "$VAULT/daily" ]
  [ -d "$VAULT/templates" ]
}

@test "obsidian: fails when vim mode not enabled" {
  mkdir -p "$TEST_HOME/Applications/Obsidian.app"
  mkdir -p "$VAULT/.obsidian" "$VAULT/daily" "$VAULT/templates"
  echo '{"vimMode": false}' > "$VAULT/.obsidian/app.json"
  source "$TEST_DOTFILES/modules/obsidian/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

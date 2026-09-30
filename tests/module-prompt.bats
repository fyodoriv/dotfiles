#!/usr/bin/env bats
# Functional tests for modules/prompt/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/dot_config"
  mkdir -p "$TEST_HOME/.config"

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
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1
      fixed "$desc"
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

  # Create source starship config
  echo 'format = "$all"' > "$TEST_DOTFILES/dot_config/starship.toml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "prompt: passes tool.starship when starship is installed" {
  if ! command -v starship >/dev/null 2>&1; then
    skip "starship not installed"
  fi
  cp "$TEST_DOTFILES/dot_config/starship.toml" "$TEST_HOME/.config/starship.toml"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$pass_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "prompt: fails when starship config is missing" {
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "prompt: fix mode copies starship config" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ -f "$TEST_HOME/.config/starship.toml" ]
}

@test "prompt: passes when starship config matches source" {
  cp "$TEST_DOTFILES/dot_config/starship.toml" "$TEST_HOME/.config/starship.toml"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "prompt: fails when starship config differs" {
  echo "wrong" > "$TEST_HOME/.config/starship.toml"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "prompt: passes with symlinked starship config" {
  ln -s "$TEST_DOTFILES/dot_config/starship.toml" "$TEST_HOME/.config/starship.toml"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "prompt: skips all checks when overridden" {
  echo "tool.starship" >> "$OVERRIDES_FILE"
  echo "managed.starship" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$skip_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

@test "prompt: fix mode installs starship config to correct path" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ -f "$TEST_HOME/.config/starship.toml" ]
  diff -q "$TEST_DOTFILES/dot_config/starship.toml" "$TEST_HOME/.config/starship.toml"
}

@test "prompt: config_valid check expression exits 0 when starship absent from PATH" {
  # Run the check expression directly in a subprocess with no starship on PATH.
  # The '! command -v starship' guard must short-circuit and return 0.
  cp "$TEST_DOTFILES/dot_config/starship.toml" "$TEST_HOME/.config/starship.toml"
  local home="$TEST_HOME"
  run env HOME="$home" PATH="/usr/bin:/bin" \
    bash -c '! command -v starship >/dev/null 2>&1 || ! [ -f "$HOME/.config/starship.toml" ] || STARSHIP_CONFIG="$HOME/.config/starship.toml" starship print-config >/dev/null 2>&1'
  [ "$status" -eq 0 ]
}

@test "prompt: config_valid check ID is discoverable via dotfiles doctor --list" {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  run "$REPO_ROOT/bin/dotfiles" doctor --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"prompt.config_valid"* ]] || {
    echo "dotfiles doctor --list does not include 'prompt.config_valid'"
    echo "fix: add check \"prompt.config_valid\" to modules/prompt/doctor.sh"
    return 1
  }
}

@test "prompt: config_valid fails when starship config has invalid TOML" {
  if ! command -v starship >/dev/null 2>&1; then
    skip "starship not installed"
  fi
  printf '[invalid toml ===\n' > "$TEST_HOME/.config/starship.toml"
  source "$BATS_TEST_DIRNAME/../modules/prompt/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

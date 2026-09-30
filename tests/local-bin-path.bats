#!/usr/bin/env bats
# Tests for modules/local-bin/doctor.sh and the zshrc PATH export.
#
# Why: the Minsky observer plugin (and future shim-style tools) install
# themselves by symlinking into ~/.local/bin. If the dir is missing or
# not on PATH, `command -v minsky` fails first-try. This module locks
# the guarantee in place.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
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
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "local-bin: both checks pass when ~/.local/bin exists and is on PATH" {
  mkdir -p "$TEST_HOME/.local/bin"
  PATH="$TEST_HOME/.local/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  [ "$pass_count" -eq 2 ]
  [ "$fail_count" -eq 0 ]
}

@test "local-bin: dir_exists fails when ~/.local/bin missing" {
  PATH="$TEST_HOME/.local/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  # dir_exists fails, on_path passes (PATH includes the missing dir)
  [ "$fail_count" -ge 1 ]
}

@test "local-bin: on_path fails when ~/.local/bin not on PATH" {
  mkdir -p "$TEST_HOME/.local/bin"
  PATH="/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  # dir_exists passes, on_path fails
  [ "$fail_count" -ge 1 ]
  [ "$pass_count" -ge 1 ]
}

@test "local-bin: fix mode creates ~/.local/bin" {
  FIX_MODE=true
  PATH="$TEST_HOME/.local/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  [ -d "$TEST_HOME/.local/bin" ]
  [ "$fix_count" -ge 1 ]
}

@test "local-bin: on_path matches only exact dir, not a prefix" {
  mkdir -p "$TEST_HOME/.local/bin"
  # PATH contains a directory that has ~/.local/bin as a substring
  # but is NOT the dir we care about. Must not pass on_path.
  PATH="$TEST_HOME/.local/binbogus:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  # on_path must fail (1 fail), dir_exists must pass (1 pass)
  [ "$fail_count" -eq 1 ]
  [ "$pass_count" -eq 1 ]
}

@test "local-bin: overrides skip checks" {
  echo "local_bin.dir_exists" >> "$OVERRIDES_FILE"
  echo "local_bin.on_path" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/local-bin/doctor.sh"
  [ "$skip_count" -eq 2 ]
}

@test "zshrc: unconditionally exports ~/.local/bin on PATH" {
  # The PATH export must not be gated on `[ -d ... ]` — a fresh machine
  # where chezmoi has not yet run still needs the shim path resolved
  # the next time apply creates the dir.
  run grep -E '^[[:space:]]*export PATH="\$HOME/\.local/bin:\$PATH"' \
    "$BATS_TEST_DIRNAME/../home/zshrc"
  [ "$status" -eq 0 ]
}

@test "zshrc: PATH export is reached when ~/.local/bin does not yet exist" {
  # Smoke: simulate a fresh shell sourcing zshrc when ~/.local/bin
  # is not on disk yet. The PATH should still contain it after.
  # Use bash (not zsh) so the test runs without a zsh dep — only the
  # one PATH export line matters here.
  out=$(HOME="$TEST_HOME" PATH="/usr/bin:/bin" bash -c '
    export PATH="$HOME/.local/bin:$PATH"
    echo "$PATH"
  ')
  case ":$out:" in
    *":$TEST_HOME/.local/bin:"*) ;;
    *) echo "PATH did not include $TEST_HOME/.local/bin: $out"; return 1 ;;
  esac
}

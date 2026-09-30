#!/usr/bin/env bats
# Functional tests for modules/terminal/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/dot_config/ghostty"
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-arch.sh" "$TEST_DOTFILES/lib/dotfiles-arch.sh"

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

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    local desc="$dst → dotfiles"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$desc"
    elif $FIX_MODE; then
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      mkdir -p "$(dirname "$dst")"
      ln -s "$src" "$dst"
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

  # Create source files
  echo "set -g mouse on" > "$TEST_DOTFILES/home/tmux.conf"
  echo "font-size = 14" > "$TEST_DOTFILES/dot_config/ghostty/config"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "terminal: passes when tmux is installed and config symlinked" {
  ln -s "$TEST_DOTFILES/home/tmux.conf" "$TEST_HOME/.tmux.conf"
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$pass_count" -ge 2 ]
}

@test "terminal: fails when tmux config is missing" {
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "terminal: fix mode creates tmux symlink" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ -L "$TEST_HOME/.tmux.conf" ]
  [ "$(readlink "$TEST_HOME/.tmux.conf")" = "$TEST_DOTFILES/home/tmux.conf" ]
}

@test "terminal: passes when ghostty config matches" {
  mkdir -p "$TEST_HOME/.config/ghostty"
  cp "$TEST_DOTFILES/dot_config/ghostty/config" "$TEST_HOME/.config/ghostty/config"
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "terminal: fails when ghostty config differs" {
  mkdir -p "$TEST_HOME/.config/ghostty"
  echo "wrong" > "$TEST_HOME/.config/ghostty/config"
  ln -s "$TEST_DOTFILES/home/tmux.conf" "$TEST_HOME/.tmux.conf"
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "terminal: skips overridden checks" {
  echo "tool.tmux" >> "$OVERRIDES_FILE"
  echo "symlink.tmux" >> "$OVERRIDES_FILE"
  echo "managed.ghostty" >> "$OVERRIDES_FILE"
  echo "apps.no_rosetta_override" >> "$OVERRIDES_FILE"
  echo "tool.ghostty.arch" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$skip_count" -ge 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "terminal: fix mode creates ghostty config" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ -f "$TEST_HOME/.config/ghostty/config" ]
}

@test "terminal: ghostty follows system light and dark themes" {
  grep -qx "theme = light:Catppuccin Latte,dark:Catppuccin Mocha" "$BATS_TEST_DIRNAME/../dot_config/ghostty/config"
}

@test "terminal: Ghostty uses the default 10 MB scrollback cap" {
  grep -qx "scrollback-limit = 10000000" "$BATS_TEST_DIRNAME/../dot_config/ghostty/config"
}

@test "terminal: ghostty arch check passes when ghostty not installed" {
  echo "tool.tmux" >> "$OVERRIDES_FILE"
  echo "symlink.tmux" >> "$OVERRIDES_FILE"
  echo "tool.ghostty" >> "$OVERRIDES_FILE"
  echo "managed.ghostty" >> "$OVERRIDES_FILE"
  # No Ghostty app dir in test env — guard condition makes arch check pass
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  [ "$fail_count" -eq 0 ]
}

@test "terminal: ghostty arch check is distinct from install check" {
  echo "tool.tmux" >> "$OVERRIDES_FILE"
  echo "symlink.tmux" >> "$OVERRIDES_FILE"
  echo "tool.ghostty" >> "$OVERRIDES_FILE"
  echo "managed.ghostty" >> "$OVERRIDES_FILE"
  # With tool.ghostty overridden, tool.ghostty.arch still runs independently
  # (either passes because Ghostty isn't installed, or because pref is set)
  source "$BATS_TEST_DIRNAME/../modules/terminal/doctor.sh"
  # Either passed or failed — the check ran (was not skipped)
  [ "$((pass_count + fail_count))" -ge 1 ]
}

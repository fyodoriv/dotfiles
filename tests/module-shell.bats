#!/usr/bin/env bats
# Functional tests for modules/shell/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.cache/zsh"
  mkdir -p "$TEST_DOTFILES/home"

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

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$dst"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      ln -s "$src" "$dst"
      fixed "$dst"
    else
      fail "$dst"
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

  # Create source files
  echo "# zshenv" > "$TEST_DOTFILES/home/zshenv"
  # Create zshrc with all expected patterns
  cat > "$TEST_DOTFILES/home/zshrc" <<'ZSHRC'
# Shell config
_dotfiles_bin="$HOME/apps/dotfiles/bin"
export NODE_OPTIONS="--max-old-space-size=8192"
ulimit -n 65535
export HOMEBREW_NO_AUTO_UPDATE=1
ZSHRC
  echo "" > "$TEST_DOTFILES/dot_hushlogin"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "shell: symlinks pass when correctly linked" {
  ln -s "$TEST_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"
  ln -s "$TEST_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ "$pass_count" -ge 2 ]
}

@test "shell: symlinks fail when missing" {
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ "$fail_count" -ge 2 ]
}

@test "shell: fix mode creates missing symlinks" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ "$fix_count" -ge 2 ]
  [ -L "$TEST_HOME/.zshenv" ]
  [ -L "$TEST_HOME/.zshrc" ]
}

@test "shell: managed hushlogin passes when content matches" {
  cp "$TEST_DOTFILES/dot_hushlogin" "$TEST_HOME/.hushlogin"
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  # hushlogin managed check should pass
  [ "$pass_count" -ge 1 ]
}

@test "shell: config checks pass when patterns present in zshrc" {
  ln -s "$TEST_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"
  ln -s "$TEST_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  cp "$TEST_DOTFILES/dot_hushlogin" "$TEST_HOME/.hushlogin"
  # Create cache files for fzf and zoxide
  echo "# fzf init" > "$TEST_HOME/.cache/zsh/fzf.zsh"
  echo "# zoxide init" > "$TEST_HOME/.cache/zsh/zoxide.zsh"
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  # 2 symlinks + 1 managed + 2 caches + 4 grep checks = 9 passes
  [ "$pass_count" -ge 8 ]
  [ "$fail_count" -eq 0 ]
}

@test "shell: config checks fail when patterns missing from zshrc" {
  # Create a zshrc without the expected patterns
  echo "# empty zshrc" > "$TEST_DOTFILES/home/zshrc"
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  # The 4 grep-based checks should fail
  [ "$fail_count" -ge 4 ]
}

@test "shell: cache checks fail when files missing" {
  ln -s "$TEST_DOTFILES/home/zshenv" "$TEST_HOME/.zshenv"
  ln -s "$TEST_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  # Don't create cache files
  rmdir "$TEST_HOME/.cache/zsh" 2>/dev/null || true
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  # fzf_cached and zoxide_cached should fail
  [ "$fail_count" -ge 2 ]
}

@test "shell: overrides skip checks" {
  echo "symlink.zshenv" >> "$OVERRIDES_FILE"
  echo "symlink.zshrc" >> "$OVERRIDES_FILE"
  echo "shell.fzf_cached" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/shell/doctor.sh"
  [ "$skip_count" -ge 3 ]
}

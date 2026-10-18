#!/usr/bin/env bats
# On a core-profile Mac, `dotfiles doctor` must not fail checks for tools
# that only the full profile installs (Ghostty, tmux, lazygit and tig
# configs, JetBrains, VS Code, agent-browser, Dock folders). On the full
# profile those checks still run.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
FULL_ONLY_MODULES="terminal jetbrains vscode agent-browser macos extras"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/fakebin" "$TEST_DIR/apps"
  # A fresh Mac can carry settings folders for IDEs that are not installed.
  for ide in WebStorm2025.1 GoLand2025.1 PyCharm2025.1 IntelliJIdea2025.1 Rider2025.1; do
    mkdir -p "$HOME/Library/Application Support/JetBrains/$ide"
  done
  export JETBRAINS_APP_DIRS="$TEST_DIR/apps"
  export VSCODE_APP="$TEST_DIR/apps/Visual Studio Code.app"
  # Present-but-broken full-only tools prove the checks are skipped, not passed.
  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/fakebin/dockutil"
  chmod +x "$TEST_DIR/fakebin/dockutil"
  export PATH="$TEST_DIR/fakebin:/usr/bin:/bin:/usr/sbin:/sbin"
  export DOTFILES_DIR="$REPO_ROOT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_fake_profile() {
  printf '#!/bin/bash\ncase "$*" in *".profile"*) echo %s ;; *) exit 1 ;; esac\n' "$1" \
    > "$TEST_DIR/fakebin/chezmoi"
  chmod +x "$TEST_DIR/fakebin/chezmoi"
}

# Prints "<status> <id>" for every check the modules report.
_doctor_results() {
  local m
  for m in $FULL_ONLY_MODULES; do
    "$REPO_ROOT/bin/dotfiles-doctor" --json --module "$m" 2>/dev/null |
      grep -oE '"id":"[^"]*","status":"[a-z]*"' |
      sed -E 's/"id":"([^"]*)","status":"([a-z]*)"/\2 \1/'
  done
}

_FULL_ONLY_IDS='^(fail) (tool\.tmux|symlink\.tmux|tool\.ghostty|managed\.ghostty|symlink\.ideavimrc|symlink\..*\.(webstorm|goland|pycharm|intellijidea|rider)|plugins\..*|vscode\..*|agent-browser\..*|macos\.dock_(applications|downloads)|tool\.dockutil|managed\.(lazygit|tigrc|gradle))$'

@test "core profile: doctor reports no failure for a full-only tool" {
  _fake_profile core
  run _doctor_results
  [ "$status" -eq 0 ]
  hits="$(printf '%s\n' "$output" | grep -E "$_FULL_ONLY_IDS" || true)"
  if [ -n "$hits" ]; then
    printf 'full-only failures on core:\n%s\n' "$hits" >&3
    return 1
  fi
}

@test "core profile: an installed JetBrains IDE is still checked" {
  _fake_profile core
  mkdir -p "$TEST_DIR/apps/WebStorm.app"
  run _doctor_results
  [[ "$output" == *"symlink.editor.webstorm"* ]]
  [[ "$output" != *"symlink.editor.goland"* ]]
}

@test "full profile: the full-only checks still run" {
  _fake_profile full
  run _doctor_results
  [[ "$output" == *" tool.tmux"* ]]
  [[ "$output" == *" managed.lazygit"* ]]
  [[ "$output" == *" symlink.ideavimrc"* ]]
  [[ "$output" == *" vscode.installed"* ]]
  [[ "$output" == *" agent-browser.installed"* ]]
  [[ "$output" == *" macos.dock_downloads"* ]]
  [[ "$output" == *"symlink.editor.goland"* ]]
}

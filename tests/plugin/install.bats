#!/usr/bin/env bats
# US-1: `dotfiles plugin add <path>` wires a tooling-app's plugin
# contributions into dotfiles + agentbrew via symlinks under
# ~/.config/dotfiles/plugins/<name>/. See docs/plugin-system.md.

DOTFILES_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
FIXTURE="$DOTFILES_DIR/tests/fixtures/plugin-fixtures/simple-plugin"

setup() {
  # Isolate to a per-test HOME so doctor/sync writes don't touch the
  # operator's real config. Every assertion below is scoped to TEST_HOME.
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-plugin-test.XXXXXX")"
  export HOME="$TEST_HOME"
  mkdir -p "$TEST_HOME/.config/dotfiles" "$TEST_HOME/.local/share/dotfiles/logs/plugins"
}

teardown() {
  if [ -n "${TEST_HOME:-}" ] && [ -d "$TEST_HOME" ] && [[ "$TEST_HOME" == /tmp/* || "$TEST_HOME" == /var/folders/* || "$TEST_HOME" == "${TMPDIR:-}"* ]]; then
    rm -rf "$TEST_HOME"
  fi
}

# ── Plugin CLI surface ──────────────────────────────────────────────

@test "bin/dotfiles-plugin exists and is executable" {
  [ -x "$DOTFILES_DIR/bin/dotfiles-plugin" ]
}

@test "bin/dotfiles-plugin has bash shebang + strict mode" {
  head -1 "$DOTFILES_DIR/bin/dotfiles-plugin" | grep -q '^#!/bin/bash'
  grep -q 'set -euo pipefail' "$DOTFILES_DIR/bin/dotfiles-plugin"
}

@test "dotfiles-plugin --help exits 0 and lists add/remove/heal/list/status" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"add"* ]]
  [[ "$output" == *"remove"* ]]
  [[ "$output" == *"heal"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"status"* ]]
}

@test "dotfiles plugin subcommand dispatches to dotfiles-plugin" {
  run "$DOTFILES_DIR/bin/dotfiles" plugin --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"add"* ]]
}

# ── US-1: `dotfiles plugin add <path>` core behavior ────────────────

@test "plugin add: requires a path argument" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add
  [ "$status" -ne 0 ]
  [[ "$output" == *"path"* || "$output" == *"usage"* || "$output" == *"Usage"* ]]
}

@test "plugin add: rejects a path that has no plugins/ folder" {
  local empty_repo="$TEST_HOME/empty-repo"
  mkdir -p "$empty_repo"
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$empty_repo" --no-sync --no-doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins/"* || "$output" == *"manifest"* || "$output" == *"not a plugin"* ]]
}

@test "plugin add: rejects a manifest with wrong schemaVersion" {
  local bad="$TEST_HOME/bad-schema"
  mkdir -p "$bad/plugins/dotfiles"
  printf 'schemaVersion: 999\nname: bad\nversion: "0.1.0"\n' > "$bad/plugins/dotfiles/manifest.yaml"
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$bad" --no-sync --no-doctor
  [ "$status" -ne 0 ]
  [[ "$output" == *"schemaVersion"* || "$output" == *"unsupported"* ]]
}

@test "plugin add: symlinks doctor module under ~/.config/dotfiles/plugins/<name>/modules/" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  local linked="$TEST_HOME/.config/dotfiles/plugins/simple-plugin/modules/test-plugin/doctor.sh"
  [ -L "$linked" ]
  # Symlink target resolves to the fixture path
  local target
  target="$(readlink "$linked")"
  [[ "$target" == *"plugin-fixtures/simple-plugin/plugins/dotfiles/doctor/test-plugin/doctor.sh" ]]
}

@test "plugin add: writes install-state.json with source path + symlinks" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  local state="$TEST_HOME/.config/dotfiles/plugins/simple-plugin/install-state.json"
  [ -f "$state" ]
  # Source path matches fixture
  grep -q "$FIXTURE" "$state"
  # Lists the doctor symlink that was created
  grep -q "modules/test-plugin/doctor.sh" "$state"
}

@test "plugin add: is idempotent — re-running on installed plugin is a no-op success" {
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  run "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* || "$output" == *"no-op"* || "$output" == *"unchanged"* ]]
}

@test "plugin list: shows installed plugin name + source path" {
  "$DOTFILES_DIR/bin/dotfiles-plugin" add "$FIXTURE" --no-sync --no-doctor
  run "$DOTFILES_DIR/bin/dotfiles-plugin" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"simple-plugin"* ]]
  [[ "$output" == *"$FIXTURE"* ]]
}

#!/usr/bin/env bats
# Issue #145 step 11b: the v1 overlay paths are gone. Leftover v1 settings
# fail with one clear line that points at `dotfiles plugin migrate` and
# docs/plugins.md, never silently.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config"
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  chmod +x "$TEST_DIR/stub/chezmoi"
  export PATH="$TEST_DIR/stub:$PATH"
  unset EXTRA_OVERLAY_ROOT EXTRA_DOCTOR_DIR EXTRA_BREWFILE EXTRA_VALIDATE_DIR EXTRA_AGENTFILE DOTFILES_PLUGINS_V2
}

teardown() {
  rm -rf "$TEST_DIR"
}

guard() {
  bash -c 'source "$1/lib/plugin.sh"; plugin_v1_guard' _ "$REPO_ROOT"
}

@test "each leftover v1 variable fails with one line naming the migration" {
  for v in EXTRA_OVERLAY_ROOT EXTRA_DOCTOR_DIR EXTRA_BREWFILE EXTRA_VALIDATE_DIR EXTRA_AGENTFILE; do
    run env "$v=/x" bash -c 'source "$1/lib/plugin.sh"; plugin_v1_guard' _ "$REPO_ROOT"
    [ "$status" -ne 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [[ "$output" == *"$v"*"dotfiles plugin migrate"*"docs/plugins.md"* ]]
  done
}

@test "a leftover chezmoi key fails the same way" {
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf 'data:\n  profile: full\n  extra_overlay_root: "/old/overlay"\n' > "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
  run guard
  [ "$status" -ne 0 ]
  [[ "$output" == *"extra_overlay_root"*"dotfiles plugin migrate"* ]]
}

@test "no v1 setting passes the guard" {
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dotfiles doctor stops with the guard line when a v1 variable is set" {
  EXTRA_OVERLAY_ROOT=/x DOTFILES_CI=true run bash "$REPO_ROOT/bin/dotfiles-doctor" --list
  [ "$status" -ne 0 ]
  [[ "$output" == *"dotfiles plugin migrate"* ]]
}

@test "dotfiles validate stops with the guard line when a v1 variable is set" {
  EXTRA_VALIDATE_DIR=/x run bash "$REPO_ROOT/bin/dotfiles-validate" --quick
  [ "$status" -ne 0 ]
  [[ "$output" == *"dotfiles plugin migrate"* ]]
}

@test "plugin commands work without DOTFILES_PLUGINS_V2" {
  run bash "$REPO_ROOT/bin/dotfiles-plugin" list
  [ "$status" -eq 0 ]
}

@test "the core has no v1 overlay code left (acceptance check from #145)" {
  cd "$REPO_ROOT"
  run bash -c "grep -rnE 'source .*oss-readiness\\.env|EXTRA_OVERLAY_ROOT|EXTRA_DOCTOR_DIR|EXTRA_BREWFILE|EXTRA_VALIDATE_DIR|EXTRA_AGENTFILE|DOTFILES_PLUGINS_V2|--no-discover' \
    bin lib modules .chezmoiscripts git-hooks home .chezmoi.yaml.tmpl | grep -v '^lib/plugin.sh:.*plugin_v1_guard\\|^lib/plugin.sh:.*_PLUGIN_V1_VARS'"
  echo "$output"
  [ -z "$output" ]
  [ ! -e bin/dotfiles-plugin-v2 ]
  [ ! -e docs/plugin-system.md ]
}

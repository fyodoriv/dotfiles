#!/usr/bin/env bats

load test_helper

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export DOTFILES_PLUGINS_LOCK="$XDG_CONFIG_HOME/dotfiles/plugins.lock"
  export PLUGIN_DIR="$TEST_DIR/fixture-plugin"
  EXTRA="$XDG_CONFIG_HOME/dotfiles/plugins/example"
  mkdir -p "$EXTRA/nested" "$PLUGIN_DIR/agentbrew"
  cat > "$PLUGIN_DIR/dotfiles-plugin.yaml" <<'YAML'
schema: 1
name: example
version: 1.0.0
capabilities:
  sudo: false
contributes:
  agentbrew: agentbrew
  agentfile_layers: [first.yaml, missing.yaml, nested/last.yaml]
YAML
  cat > "$DOTFILES_PLUGINS_LOCK" <<YAML
plugins:
  example:
    path: "$PLUGIN_DIR"
    dev: true
    capabilities_sha: "$(bash -c 'source "$1/lib/plugin.sh"; plugin_capabilities_sha "$PLUGIN_DIR/dotfiles-plugin.yaml"' _ "$REPO")"
YAML
  printf 'mcp: [base-example]\n' > "$PLUGIN_DIR/agentbrew/Agentfile.yaml"
  printf 'mcp: [first-example]\n' > "$EXTRA/first.yaml"
  printf 'mcp: [last-example]\n' > "$EXTRA/nested/last.yaml"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "plugin manifest accepts a list of optional Agentfile layers" {
  run bash -c 'source "$1/lib/plugin.sh"; plugin_validate_manifest "$PLUGIN_DIR/dotfiles-plugin.yaml"' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "plugin merge input preserves declaration order and skips missing files" {
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-extensions.sh"; plugin_agentfile_pairs' _ "$REPO"
  [ "$status" -eq 0 ]
  expected="$(printf 'example\t%s\n' "$PLUGIN_DIR/agentbrew/Agentfile.yaml" "$EXTRA/first.yaml" "$EXTRA/nested/last.yaml")"
  [ "$output" = "$expected" ]
}

@test "the apply fingerprint changes when a registered layer is edited or removed" {
  local original changed removed
  original="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  printf 'mcp: [updated-example]\n' > "$EXTRA/first.yaml"
  changed="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  [ "$original" != "$changed" ]
  rm -f "$EXTRA/first.yaml"
  removed="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  [ "$changed" != "$removed" ]
}

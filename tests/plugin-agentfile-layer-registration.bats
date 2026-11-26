#!/usr/bin/env bats

load test_helper

REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
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
  local original changed removed added
  original="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  printf 'mcp: [updated-example]\n' > "$EXTRA/first.yaml"
  changed="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  [ "$original" != "$changed" ]
  rm -f "$EXTRA/first.yaml"
  removed="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  [ "$changed" != "$removed" ]
  printf 'mcp: [new-example]\n' > "$EXTRA/missing.yaml"
  added="$(bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$1"' _ "$REPO")"
  [ "$removed" != "$added" ]
}

@test "registered layers require a verified plugin and a regular file inside its config directory" {
  printf 'mcp: [outside]\n' > "$TEST_DIR/outside.yaml"
  ln -s "$TEST_DIR" "$EXTRA/linked"
  ln -s "$TEST_DIR/outside.yaml" "$EXTRA/linked.yaml"
  yq -i '.contributes.agentfile_layers += ["linked/outside.yaml", "linked.yaml", "../outside.yaml"] | del(.contributes.agentbrew)' "$PLUGIN_DIR/dotfiles-plugin.yaml"
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-extensions.sh"; plugin_agentfile_pairs' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'example\t%s\n' "$EXTRA/first.yaml" "$EXTRA/nested/last.yaml")" ]
  mv "$EXTRA" "$TEST_DIR/old-namespace"
  ln -s "$TEST_DIR/old-namespace" "$EXTRA"
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-extensions.sh"; plugin_agentfile_pairs' _ "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm "$EXTRA"
  mv "$TEST_DIR/old-namespace" "$EXTRA"
  yq -i '.plugins.example.capabilities_sha = "sha256:wrong"' "$DOTFILES_PLUGINS_LOCK"
  run bash -c 'source "$1/lib/plugin.sh"; source "$1/lib/plugin-extensions.sh"; plugin_agentfile_pairs' _ "$REPO"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a plugin layer edit during apply prevents recording success for the new bytes" {
  local source="$TEST_DIR/source-cache"
  mkdir -p "$source"
  ln -s "$REPO/lib" "$source/lib"
  git -C "$source" init -q
  git -C "$source" add lib
  git -C "$source" -c user.name=fixture -c user.email=fixture@example.com commit -qm fixture
  source "$REPO/lib/apply-state.sh"
  local before
  before="$(apply_state_fingerprint "$source")"
  apply_state_record "$source" "$before"
  [ -f "$(apply_state_file)" ]
  printf 'mcp: [concurrent-change]\n' > "$EXTRA/first.yaml"
  apply_state_record "$source" "$before"
  [ ! -e "$(apply_state_file)" ]
}

@test "apply and the doctor fix keep allowed plugin layers and skip overrides" {
  local source="$TEST_DIR/source" global="$HOME/.config/agentbrew/Agentfile.yaml"
  mkdir -p "$source/bin" "$source/.chezmoiscripts" "$(dirname "$global")" "$TEST_DIR/shims"
  ln -s "$REPO/lib" "$source/lib"
  ln -s "$REPO/modules" "$source/modules"
  cp "$REPO/.chezmoiscripts/run_after_agentbrew-sync.sh" "$source/.chezmoiscripts/"
  cp "$REPO/bin/dotfiles-agentfile-resync" "$source/bin/"
  printf 'mcp: [shared-example]\n' > "$source/Agentfile.yaml"
  printf 'excludeAgents: [codex]\n' > "$EXTRA/missing.yaml"
  cat > "$TEST_DIR/shims/agentbrew" <<'SHIM'
#!/bin/bash
if [[ "$1 $2" == "agentfile merge" ]]; then
  shift 2
  if [[ "$1" == --help ]]; then
    echo 'Usage: agentbrew agentfile merge [options] <agentfiles...>'
    exit 0
  fi
  files=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --output ]]; then
      yq eval-all '. as $layer ireduce ({}; . *+ $layer)' "${files[@]}" > "$2" || exit 1
      if [ ! -f "$MUTATE_LAYER.mutated" ] && grep -q 'first-example' "$2"; then
        printf 'excludeAgents: [codex]\n' > "$MUTATE_LAYER.new"
        mv "$MUTATE_LAYER.new" "$MUTATE_LAYER"
        touch "$MUTATE_LAYER.mutated"
      fi
      exit 0
    fi
    files+=("$1")
    shift
  done
  exit 1
fi
[[ "$1" == sync ]]
SHIM
  chmod +x "$TEST_DIR/shims/agentbrew"
  export REAL_MKTEMP="$(command -v mktemp)"
  cat > "$TEST_DIR/shims/mktemp" <<'SHIM'
#!/bin/bash
case "$1" in
  .dotfiles-agentfile.*)
    [ "${FAIL_SNAPSHOT:-0}" != 1 ] || exit 1
    touch "$MUTATE_LAYER.snapshot-attempt"
    ;;
  */dotfiles-local-agentfile.*|*/local-agentfile.*|*/dotfiles-plugin-agentfiles.*)
    [ "${FAIL_GUARD:-0}" != 1 ] || [ ! -f "$MUTATE_LAYER.snapshot-attempt" ] || exit 1
    ;;
esac
exec "$REAL_MKTEMP" "$@"
SHIM
  chmod +x "$TEST_DIR/shims/mktemp"
  export PATH="$TEST_DIR/shims:$PATH" DOTFILES_OWNER_MACHINE=false MUTATE_LAYER="$EXTRA/first.yaml"
  printf 'mcp: [old-example]\n' > "$global"
  run env FAIL_SNAPSHOT=1 bash "$source/.chezmoiscripts/run_after_agentbrew-sync.sh"
  [ "$status" -ne 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = old-example ]
  run env FAIL_SNAPSHOT=1 DOTFILES_DIR="$source" bash "$source/bin/dotfiles-agentfile-resync"
  [ "$status" -ne 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = old-example ]
  run env FAIL_GUARD=1 bash "$source/.chezmoiscripts/run_after_agentbrew-sync.sh"
  [ "$status" -ne 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = old-example ]
  rm -f "$MUTATE_LAYER.snapshot-attempt"
  run env FAIL_GUARD=1 DOTFILES_DIR="$source" bash "$source/bin/dotfiles-agentfile-resync"
  [ "$status" -ne 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = old-example ]
  run bash "$source/.chezmoiscripts/run_after_agentbrew-sync.sh"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = "shared-example,base-example,first-example,last-example" ]
  [ "$(yq -r 'has("excludeAgents")' "$global")" = false ]
  [ -f "$MUTATE_LAYER.mutated" ]
  ! compgen -G "$EXTRA/.dotfiles-agentfile.*"
  ! compgen -G "$EXTRA/nested/.dotfiles-agentfile.*"
  # The fix rewrites the canonical file synchronously. Hold its fixture
  # lock to keep it from launching a duplicate apply in the background.
  mkdir -p "$HOME/.local/state/dotfiles/agentbrew-sync-fix.lock"
  rm "$MUTATE_LAYER.mutated"
  printf 'mcp: [first-example]\n' > "$MUTATE_LAYER"
  printf 'mcp: [stale-example]\n' > "$global"
  run env DOTFILES_DIR="$source" bash "$source/bin/dotfiles-agentfile-resync"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.mcp | join(",")' "$global")" = "shared-example,base-example,first-example,last-example" ]
  [ "$(yq -r 'has("excludeAgents")' "$global")" = false ]
  [ -f "$MUTATE_LAYER.mutated" ]
  ! compgen -G "$EXTRA/.dotfiles-agentfile.*"
  ! compgen -G "$EXTRA/nested/.dotfiles-agentfile.*"
}

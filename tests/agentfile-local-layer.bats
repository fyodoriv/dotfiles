#!/usr/bin/env bats
# Per-machine Agentfile layer (issue #259). An untracked
# ~/.config/dotfiles/Agentfile.local.yaml adds MCP servers (or skills,
# rules) on one Mac without a change to the shared Agentfile.yaml. The
# apply-time sync and the agentbrew.global_agentfile_in_sync doctor check
# both get it from lib/agentfile-layers.sh, so they merge the same list.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  unset XDG_CONFIG_HOME XDG_STATE_HOME DOTFILES_PLUGINS_LOCK
  export DOTFILES_OWNER_MACHINE=false
  LOCAL="$HOME/.config/dotfiles/Agentfile.local.yaml"
  mkdir -p "$HOME/.config/dotfiles" "$TEST_DIR/bin"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  # Stub agentbrew: `agentfile merge` writes each input after a "# layer:" line.
  cat > "$TEST_DIR/bin/agentbrew" <<'STUB'
#!/bin/bash
[ "$1 $2" = "agentfile merge" ] || exit 0
[ "${3:-}" = "--help" ] && { echo "Usage: agentbrew agentfile merge <agentfiles...>"; exit 0; }
shift 2
inputs=()
while [ $# -gt 0 ]; do
  case "$1" in --output) out="$2"; shift 2 ;; *) inputs+=("$1"); shift ;; esac
done
mkdir -p "$(dirname "$out")"
for f in "${inputs[@]}"; do echo "# layer: $(basename "$f")"; cat "$f"; done > "$out"
STUB
  chmod +x "$TEST_DIR/bin/chezmoi" "$TEST_DIR/bin/agentbrew"
}

teardown() {
  rm -rf "$TEST_DIR"
}

layers() {
  bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_optional_layers "$1"' _ "$REPO_ROOT"
}

# Runs the real apply-time sync script with the stub agentbrew.
run_sync() {
  env -i HOME="$HOME" PATH="$TEST_DIR/bin:/usr/bin:/bin" DOTFILES_OWNER_MACHINE=false \
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" bash "$REPO_ROOT/.chezmoiscripts/run_after_agentbrew-sync.sh"
}

@test "no local Agentfile: no local layer" {
  run layers
  [ "$status" -eq 0 ]
  [[ "$output" != *"Agentfile.local.yaml"* ]]
}

@test "a local Agentfile is a layer, merged after the owner rules" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  run layers
  [ "$status" -eq 0 ]
  [ "$output" = "$LOCAL" ]
  DOTFILES_OWNER_MACHINE=true run layers
  [ "${lines[0]}" = "$REPO_ROOT/config/agentfile-owner-rules.yaml" ]
  [ "${lines[1]}" = "$LOCAL" ]
}

@test "XDG_CONFIG_HOME moves the local Agentfile" {
  export XDG_CONFIG_HOME="$TEST_DIR/xdg"
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  printf 'mcp:\n  - figma\n' > "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml"
  run layers
  [ "$output" = "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml" ]
}

@test "dotfiles apply merges the local Agentfile into the global Agentfile" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -qx '# layer: Agentfile.yaml' "$global"
  grep -qx '# layer: Agentfile.local.yaml' "$global"
  grep -qx '  - figma' "$global"
  # The shared Agentfile stays the same.
  ! grep -q 'figma$' <(grep -v '^ *#' "$REPO_ROOT/Agentfile.yaml")
}

@test "the last-apply fingerprint changes when the local Agentfile changes" {
  repo="$TEST_DIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  fp() { bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$2"' _ "$REPO_ROOT" "$repo"; }
  before="$(fp)"
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  with_local="$(fp)"
  [ "$before" != "$with_local" ]
  printf 'mcp:\n  - figma\n  - other\n' > "$LOCAL"
  [ "$(fp)" != "$with_local" ]
}

@test "apply-state and agentfile-layers name the same local Agentfile path" {
  export XDG_CONFIG_HOME="$TEST_DIR/xdg"
  path="$(bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_local_layer_path' _ "$REPO_ROOT")"
  [ "$path" = "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml" ]
  grep -qF '${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml' "$REPO_ROOT/lib/apply-state.sh"
}

@test "docs name the local Agentfile" {
  grep -q 'Agentfile.local.yaml' "$REPO_ROOT/docs/agentbrew-setup.md"
  grep -q 'Agentfile.local.yaml' "$REPO_ROOT/Agentfile.yaml"
}

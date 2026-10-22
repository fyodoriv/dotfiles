#!/usr/bin/env bats
# A company plugin's Agentfile (contributes.agentbrew) may add agent hooks,
# but never drop or replace a shared one. agentbrew's merge lets a later
# hook replace every earlier hook with the same event, matcher, and agents,
# so lib/agentfile-layers.sh (agentfile_plugin_layers) merges the earlier
# layers with and without the plugin and skips a plugin Agentfile that
# would remove a hook. These tests use the real `agentbrew agentfile merge`
# and skip on a Mac without an agentbrew checkout. No network.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLI="$REPO_ROOT/bin/dotfiles-plugin"

# The real agentbrew checkout (found with the real HOME).
setup_file() {
  local co
  co="$(bash -c 'source "$1/lib/agentbrew-locate.sh"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/.." 2>/dev/null || true)"
  if [ -n "$co" ] && [ -f "$co/dist/cli.js" ] && command -v node >/dev/null 2>&1; then
    export AGENTBREW_CHECKOUT="$co" NODE_BIN="$(command -v node)"
  fi
}

setup() {
  [ -n "${AGENTBREW_CHECKOUT:-}" ] || skip "no agentbrew checkout on this Mac"
  command -v yq >/dev/null 2>&1 || skip "mikefarah yq is not installed"
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DOTFILES_OWNER_MACHINE=false
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME AGENT_PLUGINS_ALLOWED_SIGNERS XDG_STATE_HOME
  mkdir -p "$HOME" "$TEST_DIR/bin"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  # agentbrew: the real merge; every other command is a no-op (no real sync).
  cat > "$TEST_DIR/bin/agentbrew" <<STUB
#!/bin/bash
[ "\$1 \$2" = "agentfile merge" ] || exit 0
exec "$NODE_BIN" "$AGENTBREW_CHECKOUT/dist/cli.js" "\$@"
STUB
  chmod +x "$TEST_DIR/bin/chezmoi" "$TEST_DIR/bin/agentbrew"
  ln -s "$(command -v yq)" "$TEST_DIR/bin/yq"
  export AGENTFILE_AGENTBREW_CMD="$TEST_DIR/bin/agentbrew"
  ssh-keygen -q -t ed25519 -N '' -C release -f "$TEST_DIR/key"
  SRC="$TEST_DIR/dotfiles-acme"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# plugin_with_hook <matcher>: a signed plugin whose Agentfile adds figma and
# one PreToolUse hook with <matcher>, installed and locked.
# HOOKS_YAML replaces the whole hooks: list when set.
plugin_with_hook() {
  git init -q "$SRC"
  mkdir -p "$SRC/agentbrew"
  cat > "$SRC/dotfiles-plugin.yaml" <<'YAML'
schema: 1
name: acme
version: 1.0.0
capabilities:
  sudo: false
contributes:
  agentbrew: agentbrew
YAML
  {
    printf 'mcp:\n  - figma\n'
    if [ -n "${HOOKS_YAML:-}" ]; then
      printf '%s\n' "$HOOKS_YAML"
    else
      printf 'hooks:\n  - event: PreToolUse\n    matcher: %s\n    command: "~/bin/acme-log.sh"\n' "$1"
    fi
  } > "$SRC/agentbrew/Agentfile.yaml"
  git -C "$SRC" add -A
  git -C "$SRC" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -qm init
  git -C "$SRC" -c gpg.format=ssh -c user.signingkey="$TEST_DIR/key.pub" -c user.name=t -c user.email=t@example.com \
    tag -s v1.0.0 -m v1.0.0
  bash "$CLI" add "$SRC@v1.0.0" --signer "$(cat "$TEST_DIR/key.pub")" --yes >/dev/null
  PLUGIN_AGENTFILE="$XDG_DATA_HOME/dotfiles/plugins/acme/agentbrew/Agentfile.yaml"
  [ -f "$PLUGIN_AGENTFILE" ]
}

# plugin_with_hook_again: rewrites the installed plugin's Agentfile in place
# (the lock is not re-made; agentfile_plugin_layers reads the file only).
plugin_with_hook_again() {
  printf 'mcp:\n  - figma\n%s\n' "$HOOKS_YAML" > "$PLUGIN_AGENTFILE"
}

filter() {
  printf 'acme\t%s\n' "$PLUGIN_AGENTFILE" |
    bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"' _ "$REPO_ROOT"
}

run_sync() {
  env -i HOME="$HOME" PATH="$TEST_DIR/bin:/usr/bin:/bin" DOTFILES_OWNER_MACHINE=false \
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" bash "$REPO_ROOT/.chezmoiscripts/run_after_agentbrew-sync.sh"
}

doctor_hook_check() {
  PATH="$TEST_DIR/bin:/usr/bin:/bin" bash -c 'DOTFILES_DIR="$1"
    check() { [ "$1" = agentbrew.plugin_agentfile_hooks ] || return 0
      if eval "$3" >/dev/null 2>&1; then echo "PASS $2"; else echo "FAIL $2"; fi; }
    check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
}

@test "a plugin Agentfile whose hook would replace a shared hook is skipped, naming the plugin and the hook" {
  plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"PreToolUse Bash ~/.config/dotfiles/hooks/block-dangerous-git.sh"* ]]
  run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ -z "$output" ]
}

@test "a plugin hook with its own matcher is kept, and every shared hook stays" {
  plugin_with_hook Write
  run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ "$output" = "$PLUGIN_AGENTFILE" ]
  "$TEST_DIR/bin/agentbrew" agentfile merge "$REPO_ROOT/Agentfile.yaml" "$PLUGIN_AGENTFILE" --output "$TEST_DIR/merged.yaml" >/dev/null
  grep -q 'block-dangerous-git.sh' "$TEST_DIR/merged.yaml"
  grep -q 'acme-log.sh' "$TEST_DIR/merged.yaml"
}

@test "dotfiles apply keeps the shared hooks when a plugin hook would replace them" {
  plugin_with_hook Bash
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -q 'block-dangerous-git.sh' "$global"
  ! grep -q 'acme-log.sh' "$global"
  ! grep -q 'figma' "$global"
}

@test "dotfiles apply merges a plugin Agentfile whose hooks add, not replace" {
  plugin_with_hook Write
  run run_sync
  echo "$output"
  [[ "$output" == *"Including plugin Agentfile at $PLUGIN_AGENTFILE"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -q 'block-dangerous-git.sh' "$global"
  grep -q 'acme-log.sh' "$global"
  grep -q 'figma' "$global"
}

@test "doctor: the plugin hook check names the plugin and the hook" {
  plugin_with_hook Bash
  run doctor_hook_check
  echo "$output"
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"plugin acme"* ]]
  [[ "$output" == *"block-dangerous-git.sh"* ]]
}

@test "doctor: the plugin hook check passes for a hook with its own matcher" {
  plugin_with_hook Write
  run doctor_hook_check
  echo "$output"
  [[ "$output" == PASS* ]]
}

@test "a plugin cannot weaken a shared hook by re-declaring it with other fields" {
  HOOKS_YAML='hooks:
  - event: PreToolUse
    matcher: Bash
    command: "~/.config/dotfiles/hooks/block-dangerous-git.sh"
    async: true
    timeout: 1
  - event: PreToolUse
    matcher: Bash
    command: "~/.config/dotfiles/hooks/prepend-endpoint-path.sh"
  - event: PreToolUse
    matcher: Bash
    command: "~/bin/acme-log.sh"' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"block-dangerous-git.sh"* ]]
}

@test "without agentfile merge, a plugin Agentfile with hooks is skipped and one without is kept" {
  plugin_with_hook Write
  AGENTFILE_AGENTBREW_CMD=false run filter
  echo "$output"
  [[ "$output" == *"it has hooks:"* ]]
  HOOKS_YAML='skills: []' plugin_with_hook_again
  AGENTFILE_AGENTBREW_CMD=false run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ "$output" = "$PLUGIN_AGENTFILE" ]
}

@test "doctor: with no agentbrew on PATH, the hook check uses the checkout, as apply does" {
  plugin_with_hook Bash
  mkdir -p "$TEST_DIR/noab"
  ln -s "$NODE_BIN" "$TEST_DIR/noab/node"
  ln -s "$(command -v yq)" "$TEST_DIR/noab/yq"
  base="$(dirname "$AGENTBREW_CHECKOUT")"
  [ "$(basename "$base")" != tooling ] || base="$(dirname "$base")"
  run env -u AGENTFILE_AGENTBREW_CMD PATH="$TEST_DIR/noab:/usr/bin:/bin" DOTFILES_REPOS_DIR="$base" bash -c 'DOTFILES_DIR="$1"
    check() { [ "$1" = agentbrew.plugin_agentfile_hooks ] || return 0
      if eval "$3" >/dev/null 2>&1; then echo "PASS $2"; else echo "FAIL $2"; fi; }
    check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
  echo "$output"
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"block-dangerous-git.sh"* ]]
}

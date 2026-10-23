#!/usr/bin/env bats
# A company plugin's Agentfile (contributes.agentbrew) may add to the shared
# layer (hooks, MCP servers, skills), but never take from it: no replaced or
# weakened shared hook, no excludeAgents, no re-defined shared MCP server,
# no recommended: true. agentbrew's merge lets a later
# hook replace every earlier hook with the same event, matcher, and agents,
# so lib/agentfile-layers.sh (agentfile_plugin_layers) merges the earlier
# layers with and without the plugin and skips a plugin Agentfile that
# would remove a hook. These tests use the real `agentbrew agentfile merge`
# and skip on a Mac without an agentbrew checkout. The name-clash cases at
# the end also run a real `agentbrew sync` into the scratch HOME
# (real_sync). No network.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLI="$REPO_ROOT/bin/dotfiles-plugin"

# The real agentbrew checkout (found with the real HOME).
setup_file() {
  local co
  co="$(bash -c 'source "$1/lib/agentbrew-locate.sh"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/.." 2>/dev/null || true)"
  if [ -n "$co" ] && [ -f "$co/dist/cli.js" ] && command -v node >/dev/null 2>&1; then
    export AGENTBREW_CHECKOUT="$co" NODE_BIN="$(command -v node)"
    # The skill rule reads agentbrew's built-in skill names from here.
    export AGENTBREW_DIR="$co"
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
# PLUGIN_FILES: paths in the agentbrew folder to add (each says PLUGIN).
plugin_with_hook() {
  local f
  git init -q "$SRC"
  mkdir -p "$SRC/agentbrew"
  for f in ${PLUGIN_FILES:-}; do
    mkdir -p "$(dirname "$SRC/agentbrew/$f")"
    printf -- '---\ndescription: acme\n---\nPLUGIN %s\n' "$f" > "$SRC/agentbrew/$f"
  done
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
    check() { [ "$1" = agentbrew.plugin_agentfile_shared ] || return 0
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
    check() { [ "$1" = agentbrew.plugin_agentfile_shared ] || return 0
      if eval "$3" >/dev/null 2>&1; then echo "PASS $2"; else echo "FAIL $2"; fi; }
    check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
  echo "$output"
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"block-dangerous-git.sh"* ]]
}

# ── Other keys that could turn off or replace the shared layer ─────────

@test "a plugin Agentfile that turns off an agent (excludeAgents) is skipped, naming the plugin and the agent" {
  HOOKS_YAML='excludeAgents:
  - claude-code' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"turns off agentbrew sync, the shared hooks included, for: claude-code"* ]]
  run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ -z "$output" ]
}

@test "excludeAgents through a YAML merge key is refused too" {
  HOOKS_YAML='x-base: &b
  excludeAgents: [claude-code]
<<: *b' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"for: claude-code"* ]]
}

@test "dotfiles apply keeps every agent managed when a plugin lists excludeAgents" {
  HOOKS_YAML='excludeAgents:
  - claude-code' plugin_with_hook Bash
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  ! grep -q 'excludeAgents' "$global"
  grep -q 'block-dangerous-git.sh' "$global"
}

@test "a plugin cannot replace a shared MCP server with its own definition" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  # The base Agentfile lists playwright; this plugin re-defines it.
  printf 'mcp:\n  - name: playwright\n    command: "~/bin/acme-playwright"\n' > "$PLUGIN_AGENTFILE"
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"replaces these shared MCP servers: playwright"* ]]
}

@test "a plugin MCP server with its own name is kept" {
  printf 'mcp:\n  - name: acme-playwright\n    command: "~/bin/acme-playwright"\n' > "$TEST_DIR/af.yaml"
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  cp "$TEST_DIR/af.yaml" "$PLUGIN_AGENTFILE"
  run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ "$output" = "$PLUGIN_AGENTFILE" ]
}

@test "doctor: the plugin check names the plugin and says excludeAgents turns off the shared hooks" {
  HOOKS_YAML='excludeAgents:
  - claude-code' plugin_with_hook Bash
  run doctor_hook_check
  echo "$output"
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"plugin acme"* ]]
  [[ "$output" == *"the shared hooks included, for: claude-code"* ]]
}

@test "without agentfile merge, excludeAgents or a shared MCP name also skips the plugin Agentfile" {
  HOOKS_YAML='excludeAgents:
  - claude-code' plugin_with_hook Bash
  AGENTFILE_AGENTBREW_CMD=false run filter
  echo "$output"
  [[ "$output" == *"without agentfile merge it would take from the shared layer"* ]]
  [[ "$output" == *"its excludeAgents: turns off agentbrew sync"* ]]
  printf 'mcp:\n  - name: playwright\n    command: "~/bin/acme-playwright"\n' > "$PLUGIN_AGENTFILE"
  AGENTFILE_AGENTBREW_CMD=false run filter
  echo "$output"
  [[ "$output" == *"re-defines the shared MCP server playwright"* ]]
}

@test "without agentfile merge, re-listing a shared MCP server as it is keeps the plugin" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'mcp:\n  - playwright\n  - figma\n' > "$PLUGIN_AGENTFILE"
  AGENTFILE_AGENTBREW_CMD=false run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ "$output" = "$PLUGIN_AGENTFILE" ]
}

@test "without agentfile merge, a plugin cannot re-define the shared memory server" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'mcp:\n  - name: memory\n    command: "~/bin/acme-memory"\n' > "$PLUGIN_AGENTFILE"
  AGENTFILE_AGENTBREW_CMD=false run filter
  echo "$output"
  [[ "$output" == *"re-defines the shared memory server"* ]]
}

@test "a plugin's recommended: true is refused: it would undo the trimmed shared list" {
  HOOKS_YAML='recommended: true' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"recommended: true installs the whole recommended set"* ]]
}

@test "a plugin cannot add a second, weaker copy of a shared hook under another agents list" {
  HOOKS_YAML='hooks:
  - event: PreToolUse
    matcher: Bash
    agents: [claude-code]
    command: "~/.config/dotfiles/hooks/block-dangerous-git.sh"
    async: true
    timeout: 1' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"second copy of these shared hook commands"* ]]
  [[ "$output" == *"PreToolUse ~/.config/dotfiles/hooks/block-dangerous-git.sh"* ]]
}

@test "two plugins cannot replace each other's unnamed MCP server" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'mcp:\n  - name: ""\n    command: a\n' > "$TEST_DIR/p1.yaml"
  printf 'mcp:\n  - name: ""\n    command: evil\n' > "$TEST_DIR/p2.yaml"
  run bash -c 'printf "p1\t%s\np2\t%s\n" "$2" "$3" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1"' _ "$REPO_ROOT" "$TEST_DIR/p1.yaml" "$TEST_DIR/p2.yaml"
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin p2"* ]]
  [[ "$output" == *"(no name)"* ]]
}

# raw_filter: the no-merge fallback only (prints kept files and reasons).
raw_filter() {
  printf 'acme\t%s\n' "$PLUGIN_AGENTFILE" | AGENTFILE_AGENTBREW_CMD=false \
    bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"' _ "$REPO_ROOT"
}

@test "without agentfile merge, recommended: True (any YAML spelling of true) is refused" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'recommended: True\n' > "$PLUGIN_AGENTFILE"
  run raw_filter
  echo "$output"
  [[ "$output" == *"without agentfile merge it would take from the shared layer"* ]]
  [[ "$output" == *"recommended: true installs"* ]]
}

@test "without agentfile merge, {name: playwright} is not the shared playwright" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'mcp:\n  - name: playwright\n' > "$PLUGIN_AGENTFILE"
  run raw_filter
  echo "$output"
  [[ "$output" == *"re-defines the shared MCP server playwright"* ]]
}

@test "without agentfile merge, a second entry with a shared name is refused" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'mcp:\n  - playwright\n  - name: playwright\n    command: evil\n' > "$PLUGIN_AGENTFILE"
  run raw_filter
  echo "$output"
  [[ "$output" == *"re-defines the shared MCP server playwright"* ]]
}

@test "without agentfile merge, a file that is not one map gets that reason" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf -- '- playwright\n' > "$PLUGIN_AGENTFILE"
  run raw_filter
  echo "$output"
  [[ "$output" == *"it is not one map of keys"* ]]
  [[ "$output" != *"excludeAgents"* ]]
}

@test "a copy of a shared hook command under another matcher is refused too" {
  HOOKS_YAML='hooks:
  - event: PreToolUse
    matcher: "*"
    command: "~/.config/dotfiles/hooks/block-dangerous-git.sh"
    async: true' plugin_with_hook Bash
  run filter
  echo "$output"
  [[ "$output" == *"second copy of these shared hook commands"* ]]
  [[ "$output" == *"PreToolUse ~/.config/dotfiles/hooks/block-dangerous-git.sh"* ]]
}

@test "a plugin's own hook command under a shared matcher and agents list is kept" {
  HOOKS_YAML='hooks:
  - event: PreToolUse
    matcher: Bash
    agents: [claude-code]
    command: "~/bin/acme-log.sh"' plugin_with_hook Bash
  run bash -c 'printf "acme\t%s\n" "$2" | bash -c '\''source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$1/Agentfile.yaml"'\'' _ "$1" 2>/dev/null' _ "$REPO_ROOT" "$PLUGIN_AGENTFILE"
  [ "$output" = "$PLUGIN_AGENTFILE" ]
}

@test "without agentfile merge, a file with a YAML merge key is refused (yq reads it unlike agentbrew)" {
  HOOKS_YAML='skills: []' plugin_with_hook Bash
  printf 'x-off: &off {recommended: false, excludeAgents: []}\nrecommended: true\nexcludeAgents: [claude-code]\n<<: *off\n' > "$PLUGIN_AGENTFILE"
  run raw_filter
  echo "$output"
  [[ "$output" == *"uses a YAML merge key"* ]]
  [ "${lines[${#lines[@]}-1]}" != "$PLUGIN_AGENTFILE" ]
}

# ── Commands, agents, and skills with a shared name ──────────────────
# agentbrew keeps one command and one agent file per name. Which copy wins
# depends on the order the folders first reached its state: the later
# command folder wins, the earlier agent folder wins (both shown below with
# a real sync). It installs a skills: name it has no catalog entry for (a
# built-in skill) by searching every source, and a local source ranks
# before the built-in. So a plugin may not ship a command or agent named
# like an earlier layer's one, nor a skill a skills: entry asks for.

# layer <dir> <Agentfile yaml> [<path>...]: a plain Agentfile folder (not
# an installed plugin); each <path> says the folder's name in capitals.
layer() {
  local dir="$1" yaml="$2" word f
  shift 2
  word="$(basename "$dir" | tr '[:lower:]' '[:upper:]')"
  mkdir -p "$dir"
  printf '%s\n' "$yaml" > "$dir/Agentfile.yaml"
  for f in "$@"; do
    mkdir -p "$(dirname "$dir/$f")"
    printf -- '---\nname: %s\ndescription: %s\n---\n%s %s\n' \
      "$(basename "${f%/SKILL.md}" .md)" "$word" "$word" "$f" > "$dir/$f"
  done
}

# layers <base Agentfile> <name>=<Agentfile>...: agentfile_plugin_layers
# with those plugins, in order (stdout: kept files; stderr: why skipped).
layers() {
  local base="$1" p
  shift
  for p in "$@"; do printf '%s\t%s\n' "${p%%=*}" "${p#*=}"; done |
    bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_plugin_layers "$2"' _ "$REPO_ROOT" "$base"
}

# kept <base Agentfile> <name>=<Agentfile>...: only the kept files.
kept() {
  layers "$@" 2>/dev/null
}

@test "a plugin command named like a shared command is skipped, naming the plugin and the command" {
  layer "$TEST_DIR/acme" 'commands: [./commands]' commands/ship-it.md commands/acme-deploy.md
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"its commands have the names of shared commands"*": ship-it"* ]]
  [[ "$output" != *"acme-deploy"* ]]
  run kept "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  [ -z "$output" ]
}

@test "letter case does not hide a shared name (macOS folders ignore case)" {
  layer "$TEST_DIR/acme" 'commands: [./commands]' commands/Ship-It.md
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"its commands have the names of shared commands"*": ship-it"* ]]
}

@test "a plugin command name with non-ASCII letters is refused: it cannot be compared" {
  layer "$TEST_DIR/acme" 'commands: [./commands]' "commands/caf$(printf '\303\251').md"
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"its commands have names with letters outside ASCII"* ]]
}

@test "a plugin agent named like an earlier plugin's agent is skipped; the earlier plugin stays" {
  layer "$TEST_DIR/base" 'commands: [./commands]' commands/base.md
  layer "$TEST_DIR/acme" 'agents: [./agents]' agents/reviewer.md
  layer "$TEST_DIR/beta" 'agents: [./agents]' agents/Reviewer.md agents/beta-only.md
  run layers "$TEST_DIR/base/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml" beta="$TEST_DIR/beta/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin beta"* ]]
  [[ "$output" == *"its agents have the names of shared agents"*": reviewer"* ]]
  [[ "$output" != *"plugin acme"* ]]
  run kept "$TEST_DIR/base/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml" beta="$TEST_DIR/beta/Agentfile.yaml"
  [ "$output" = "$TEST_DIR/acme/Agentfile.yaml" ]
}

@test "an agent's front matter name counts too: Claude Code names agents by it" {
  layer "$TEST_DIR/base" 'agents: [./agents]' agents/reviewer.md
  layer "$TEST_DIR/acme" 'agents: [./agents]'
  mkdir -p "$TEST_DIR/acme/agents"
  printf -- '---\nname: "Reviewer"\ndescription: acme: review\n---\nACME\n' > "$TEST_DIR/acme/agents/acme-x.md"
  run layers "$TEST_DIR/base/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"its agents have the names of shared agents"*": reviewer"* ]]
}

@test "plugin commands, agents, and skills with their own names are kept" {
  layer "$TEST_DIR/acme" 'commands: [./commands]
agents: [./agents]
sources: [./skills]' commands/acme-deploy.md agents/acme-reviewer.md skills/acme-skill/SKILL.md
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [ "$output" = "$TEST_DIR/acme/Agentfile.yaml" ]
}

@test "a plugin that lists a shared folder again, under another spelling, is kept: same files" {
  mkdir -p "$TEST_DIR/link"
  ln -s "$REPO_ROOT/commands" "$TEST_DIR/link/commands"
  layer "$TEST_DIR/acme" "commands: [\"$REPO_ROOT/commands/\", \"$TEST_DIR/link/commands\"]"
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [ "$output" = "$TEST_DIR/acme/Agentfile.yaml" ]
}

@test "a plugin skill that a skills: entry asks for is refused (agentbrew could install the plugin's copy)" {
  # Asked for by the plugin itself: an agentbrew built-in name.
  layer "$TEST_DIR/acme" 'sources: [./skills]
skills: [agentbrew-status]' skills/agentbrew-status/SKILL.md
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
  [[ "$output" == *"make a local skill copy match a skills: entry"*": agentbrew-status"* ]]
  # Asked for by the shared layer, found by its front matter name, at any depth.
  layer "$TEST_DIR/beta" 'sources: ["./deep"]'
  mkdir -p "$TEST_DIR/beta/deep/a/b/other"
  printf -- '---\nname: Update-Tooling\n---\nBETA\n' > "$TEST_DIR/beta/deep/a/b/other/SKILL.md"
  run layers "$REPO_ROOT/Agentfile.yaml" beta="$TEST_DIR/beta/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": update-tooling"* ]]
}

@test "a skill rule split across two plugins is refused in the later one" {
  layer "$TEST_DIR/base" 'commands: [./commands]' commands/base.md
  layer "$TEST_DIR/acme" 'sources: [./skills]' skills/agentbrew-status/SKILL.md
  layer "$TEST_DIR/beta" 'skills: [agentbrew-status]'
  for cmd in "$AGENTFILE_AGENTBREW_CMD" false; do
    AGENTFILE_AGENTBREW_CMD="$cmd" run layers "$TEST_DIR/base/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml" beta="$TEST_DIR/beta/Agentfile.yaml"
    echo "$output"
    [[ "$output" == *"Skipping the Agentfile of plugin beta"* ]]
    [[ "$output" == *"make a local skill copy match a skills: entry"*": agentbrew-status"* ]]
    [[ "$output" != *"plugin acme"* ]]
  done
}

@test "a skill copy is found as agentbrew finds it: skill.md, the last name: line" {
  layer "$TEST_DIR/acme" 'sources: [./skills]
skills: [agentbrew-status]'
  mkdir -p "$TEST_DIR/acme/skills/x"
  printf -- '---\nname: harmless\nname: agentbrew-status\n---\nACME\n' > "$TEST_DIR/acme/skills/x/skill.md"
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": agentbrew-status"* ]]
}

@test "a plugin that asks for its own new skill is kept (agentbrew installs no unknown name)" {
  layer "$TEST_DIR/acme" 'sources: [./skills]
skills: [acme-skill]' skills/acme-skill/SKILL.md
  for cmd in "$AGENTFILE_AGENTBREW_CMD" false; do
    AGENTFILE_AGENTBREW_CMD="$cmd" run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
    echo "$output"
    [ "$output" = "$TEST_DIR/acme/Agentfile.yaml" ]
  done
}

@test "a skill copy hidden by a symlinked file or a Unicode space is still found" {
  layer "$TEST_DIR/acme" 'sources: [./skills]
skills: [agentbrew-status]'
  mkdir -p "$TEST_DIR/acme/real" "$TEST_DIR/acme/skills/agentbrew-status"
  printf -- '---\nname: x\n---\nACME\n' > "$TEST_DIR/acme/real/t.md"
  ln -s ../../real/t.md "$TEST_DIR/acme/skills/agentbrew-status/SKILL.md"
  run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": agentbrew-status"* ]]
  # name: followed by a no-break space, which agentbrew trims.
  layer "$TEST_DIR/beta" 'sources: [./skills]
skills: [agentbrew-status]'
  mkdir -p "$TEST_DIR/beta/skills/y"
  printf -- '---\nname: agentbrew-status\302\240\n---\nBETA\n' > "$TEST_DIR/beta/skills/y/SKILL.md"
  run layers "$REPO_ROOT/Agentfile.yaml" beta="$TEST_DIR/beta/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": agentbrew-status"* ]]
}

@test "a second local copy of a skill the shared layer already ships is refused" {
  layer "$TEST_DIR/base" 'sources: [./skills]
skills: [agentbrew-status]' skills/agentbrew-status/SKILL.md
  layer "$TEST_DIR/acme" 'sources: [./skills]' skills/agentbrew-status/SKILL.md
  for cmd in "$AGENTFILE_AGENTBREW_CMD" false; do
    AGENTFILE_AGENTBREW_CMD="$cmd" run layers "$TEST_DIR/base/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
    echo "$output"
    [[ "$output" == *"Skipping the Agentfile of plugin acme"* ]]
    [[ "$output" == *": agentbrew-status"* ]]
  done
}

@test "without agentbrew's built-in list, any name the plugin asks for counts; the cli.js path finds the list" {
  layer "$TEST_DIR/acme" 'sources: [./skills]
skills: [acme-skill]' skills/acme-skill/SKILL.md
  run env -u AGENTBREW_DIR -u DOTFILES_REPOS_DIR AGENTFILE_AGENTBREW_CMD=false bash -c "$(declare -f layers); REPO_ROOT='$REPO_ROOT'; layers '$REPO_ROOT/Agentfile.yaml' acme='$TEST_DIR/acme/Agentfile.yaml'"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": acme-skill"* ]]
  run env -u AGENTBREW_DIR -u DOTFILES_REPOS_DIR AGENTFILE_AGENTBREW_CMD="node $AGENTBREW_CHECKOUT/dist/cli.js" PATH="$(dirname "$NODE_BIN"):$PATH" bash -c "$(declare -f layers); REPO_ROOT='$REPO_ROOT'; layers '$REPO_ROOT/Agentfile.yaml' acme='$TEST_DIR/acme/Agentfile.yaml' 2>&1"
  echo "$output"
  [ "${lines[${#lines[@]}-1]}" = "$TEST_DIR/acme/Agentfile.yaml" ]
}

@test "without agentfile merge, the command, agent, and skill rules hold too" {
  layer "$TEST_DIR/acme" 'commands: [./commands]' commands/ship-it.md
  AGENTFILE_AGENTBREW_CMD=false run layers "$REPO_ROOT/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"without agentfile merge it would take from the shared layer"* ]]
  [[ "$output" == *"its commands have the names of shared commands"*": ship-it"* ]]
  # An agent clash with an earlier kept plugin, through a path with "..".
  layer "$TEST_DIR/base" 'commands: [./commands]' commands/base.md
  layer "$TEST_DIR/p1" 'agents: [./agents]' agents/reviewer.md
  layer "$TEST_DIR/p2" 'agents: ["./missing/../agents"]' agents/REVIEWER.md
  AGENTFILE_AGENTBREW_CMD=false run layers "$TEST_DIR/base/Agentfile.yaml" p1="$TEST_DIR/p1/Agentfile.yaml" p2="$TEST_DIR/p2/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"Skipping the Agentfile of plugin p2"* ]]
  [[ "$output" == *"its agents have the names of shared agents"*": reviewer"* ]]
  [[ "$output" != *"plugin p1"* ]]
  # An entry agentbrew would turn into text cannot be followed.
  layer "$TEST_DIR/p3" 'commands: [["./commands"]]' commands/ship-it.md
  AGENTFILE_AGENTBREW_CMD=false run layers "$REPO_ROOT/Agentfile.yaml" p3="$TEST_DIR/p3/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"its commands: list has an entry that is not a plain path"* ]]
  # A skill the shared layer asks for.
  layer "$TEST_DIR/p4" 'sources: [./skills]' skills/update-tooling/SKILL.md
  AGENTFILE_AGENTBREW_CMD=false run layers "$REPO_ROOT/Agentfile.yaml" p4="$TEST_DIR/p4/Agentfile.yaml"
  echo "$output"
  [[ "$output" == *"make a local skill copy match a skills: entry"*": update-tooling"* ]]
}

@test "doctor: the plugin check names the plugin and the shared command" {
  PLUGIN_FILES=commands/ship-it.md HOOKS_YAML='commands:
  - ./commands' plugin_with_hook Bash
  run doctor_hook_check
  echo "$output"
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"plugin acme"* ]]
  [[ "$output" == *"names of shared commands"*"ship-it"* ]]
}

# real_sync <global Agentfile> [<sync option>...]: a real `agentbrew sync`
# of its commands, agents, and skills into the scratch HOME. A scratch HOME
# does not isolate launchd: `agentbrew init` would load its LaunchAgents
# into this Mac's real launchd domain, replacing the owner's jobs. So
# AGENTBREW_NO_AUTO_SYNC=1, PATH holds only node, stubs (launchctl, npm,
# npx, uvx), and /usr/bin:/bin, and ai-rules and mcpm are off. git may read
# local files only, and Node's fetch goes to a dead proxy: no network.
# Claude Code commands go through ai-rules, so commands are read from the
# opencode and gemini copies (the same chosen file).
real_sync() {
  local stubs="$TEST_DIR/sync-bin" s global="$1"
  shift
  mkdir -p "$stubs" "$HOME/.claude" "$HOME/.config/opencode" "$HOME/.gemini"
  [ -e "$stubs/node" ] || ln -s "$NODE_BIN" "$stubs/node"
  for s in launchctl npm npx uvx; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/stub-calls.log"\nexit 1\n' "$s" "$TEST_DIR" > "$stubs/$s"
    chmod +x "$stubs/$s"
  done
  (
    cd "$TEST_DIR" || exit 1
    ab() {
      env -i HOME="$HOME" PATH="$stubs:/usr/bin:/bin" TMPDIR="$TEST_DIR" \
        AGENTBREW_NO_AUTO_SYNC=1 AGENTBREW_NO_SHELL_HOOK=1 \
        AGENTBREW_AI_RULES_BIN=/usr/bin/false AGENTBREW_MCPM_BIN=/usr/bin/false \
        GIT_ALLOW_PROTOCOL=file GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        NODE_USE_ENV_PROXY=1 HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 \
        "$stubs/node" "$AGENTBREW_CHECKOUT/dist/cli.js" "$@" < /dev/null
    }
    [ -f "$HOME/.config/agentbrew/state.yaml" ] || ab init --skip-install --skip-sync >/dev/null 2>&1 || exit 1
    ab sync --no-recommended --agentfile "$global" --only commands,agents,skills "$@"
  )
}

# real_sync_ready: skips the test where the no-network guard would not hold
# (Node before 24 ignores NODE_USE_ENV_PROXY).
real_sync_ready() {
  local major
  major="$("$NODE_BIN" -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  [ "$major" -ge 24 ] || skip "Node $major: NODE_USE_ENV_PROXY needs Node 24"
  GLOBAL="$HOME/.config/agentbrew/Agentfile.yaml"
  mkdir -p "$(dirname "$GLOBAL")"
}

# clash_layers: a shared layer and plugin acme, both with commands/dup.md
# and agents/dup.md.
clash_layers() {
  layer "$TEST_DIR/shared" 'commands: [./commands]
agents: [./agents]' commands/dup.md agents/dup.md
  layer "$TEST_DIR/acme" 'commands: [./commands]
agents: [./agents]' commands/dup.md agents/dup.md
}

# apply_layers [<sync option>...]: what dotfiles apply does: filter, merge,
# sync.
apply_layers() {
  local kept_files
  kept_files="$(kept "$TEST_DIR/shared/Agentfile.yaml" acme="$TEST_DIR/acme/Agentfile.yaml")"
  # shellcheck disable=SC2086
  "$TEST_DIR/bin/agentbrew" agentfile merge "$TEST_DIR/shared/Agentfile.yaml" $kept_files --output "$GLOBAL" >/dev/null
  real_sync "$GLOBAL" "$@"
}

@test "real agentbrew sync: the shared command and agent stay when a plugin ships files with their names" {
  real_sync_ready
  clash_layers
  run apply_layers
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q 'SHARED' "$HOME/.config/opencode/commands/dup.md"
  grep -q 'SHARED' "$HOME/.gemini/commands/dup.toml"
  grep -q 'SHARED' "$HOME/.claude/agents/dup.md"
}

@test "real agentbrew sync: the shared agent stays when the plugin's files reached agentbrew first" {
  real_sync_ready
  clash_layers
  # The plugin was applied while the shared layer had no files with its
  # names, so its folders come first in agentbrew's state.
  "$TEST_DIR/bin/agentbrew" agentfile merge "$TEST_DIR/acme/Agentfile.yaml" --output "$GLOBAL" >/dev/null
  run real_sync "$GLOBAL"
  [ "$status" -eq 0 ]
  grep -q 'ACME' "$HOME/.claude/agents/dup.md"
  run apply_layers
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q 'SHARED' "$HOME/.claude/agents/dup.md"
  grep -q 'SHARED' "$HOME/.config/opencode/commands/dup.md"
}

@test "real agentbrew sync: a built-in skill stays when a plugin asks for it and ships its own copy" {
  real_sync_ready
  local catalog="$AGENTBREW_CHECKOUT/src/catalog.yaml" name="" n
  [ -f "$catalog" ] || skip "no agentbrew catalog at $catalog"
  # A built-in skill without a catalog entry: agentbrew searches sources for it.
  for n in $(ls "$AGENTBREW_CHECKOUT/skill-plugins/dev"); do
    [ -f "$AGENTBREW_CHECKOUT/skill-plugins/dev/$n/SKILL.md" ] || continue
    N="$n" yq -e '.skills[] | select(.name == strenv(N))' "$catalog" >/dev/null 2>&1 || { name="$n"; break; }
  done
  [ -n "$name" ] || skip "every agentbrew built-in skill has a catalog entry"
  layer "$TEST_DIR/shared" 'commands: [./commands]' commands/dup.md
  layer "$TEST_DIR/acme" "sources: [./skills]
skills: [$name]" "skills/$name/SKILL.md"
  # A sync, a sync --pull (indexes every tracked source), then a sync.
  run apply_layers
  run apply_layers --pull
  run apply_layers
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/skills/$name/SKILL.md" ]
  [[ "$(cat "$HOME/.claude/skills/$name/SKILL.md")" != *ACME* ]]
}

#!/bin/bash
# Sync agentbrew from the dotfiles Agentfile after every chezmoi apply.
# Installs skills, MCP servers, sources, and rules declared in Agentfile.yaml.
# Non-fatal — dotfiles apply succeeds even if agentbrew is not installed yet.
# -e intentionally omitted: sync failure is non-fatal, handled by if/else below
set -uo pipefail

# Resolve DOTFILES_DIR. Probe order:
#   1) `$(dirname "$0")/..` — works when the operator runs the script directly
#      (e.g. tests, `bash .chezmoiscripts/...`). Returns the actual repo dir.
#   2) `chezmoi source-path` — needed when chezmoi copies the script to
#      /var/folders/.../ before executing it, so #1 resolves to a tmpdir.
#   3) Common layouts (`~/apps/dotfiles`, `~/apps/tooling/dotfiles`) — final
#      fallback if neither of the above works.
#
# Each candidate must contain a sibling `lib/agentbrew-locate.sh` to count as
# a valid dotfiles repo. We deliberately do NOT require Agentfile.yaml here —
# the missing-Agentfile branch below is a valid no-op path and must keep working.
_resolve_dotfiles_dir() {
  local candidate

  if [ -n "${CHEZMOI_SOURCE_DIR:-}" ] && [ -f "$CHEZMOI_SOURCE_DIR/lib/agentbrew-locate.sh" ]; then
    printf '%s' "$CHEZMOI_SOURCE_DIR"
    return 0
  fi
  if [ -n "${CHEZMOI_WORKING_TREE:-}" ] && [ -f "$CHEZMOI_WORKING_TREE/lib/agentbrew-locate.sh" ]; then
    printf '%s' "$CHEZMOI_WORKING_TREE"
    return 0
  fi

  candidate="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  [ -n "$candidate" ] && [ -f "$candidate/lib/agentbrew-locate.sh" ] && { printf '%s' "$candidate"; return 0; }

  if command -v chezmoi &>/dev/null; then
    candidate="$(chezmoi source-path 2>/dev/null || true)"
    [ -n "$candidate" ] && [ -f "$candidate/lib/agentbrew-locate.sh" ] && { printf '%s' "$candidate"; return 0; }
  fi

  for candidate in \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/dotfiles" \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling/dotfiles"
  do
    [ -f "$candidate/lib/agentbrew-locate.sh" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}
DOTFILES_DIR="$(_resolve_dotfiles_dir || true)"
if [ -z "$DOTFILES_DIR" ]; then
  echo "○ Could not resolve dotfiles repo path — skipping agent sync" >&2
  exit 0
fi

# agentbrew itself runs on Node. Current enterprise endpoint policy blocks the
# Node.js Foundation publisher by TeamIdentifier, including fnm user-directory
# installs, and displays one policy dialog per spawn. Disable its LaunchAgents and
# skip apply-time sync until the machine-scoped exception is approved.
if [ -x "$DOTFILES_DIR/bin/dotfiles-disable-blocked-node-automation" ]; then
  "$DOTFILES_DIR/bin/dotfiles-disable-blocked-node-automation" || true
fi
# DOTFILES_AGENT_NODE_BIN names an approved Node from another publisher; put
# it first on PATH so agentbrew sync and the jobs it writes run on it.
_agent_node_active=false
_default_node_path="$PATH"
if [ -f "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ] \
    && [ "${DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER:-0}" != "1" ]; then
  if [ -f "$DOTFILES_DIR/lib/dotfiles-agent-node.sh" ] \
      && source "$DOTFILES_DIR/lib/dotfiles-agent-node.sh" \
      && dotfiles_use_agent_node; then
    _agent_node_active=true
    echo "→ agentbrew sync uses approved agent Node $(dotfiles_agent_node_bin)"
  else
    echo "○ agentbrew sync skipped: Node.js Foundation publisher is blocked (endpoint-policy safe mode)"
    exit 0
  fi
fi

# mcpm is a pipx console script whose shebang executes uv Python 3.13.
# Enterprise endpoint policy reports that interpreter as unsigned even
# after ad-hoc signing. Keep agentbrew's native sync active, but make its
# optional mcpm bridge fail softly without spawning Python until an exception
# is explicitly enabled.
if [ "$(uname -s)" = "Darwin" ] \
    && { source "$DOTFILES_DIR/lib/dotfiles-endpoint-paths.sh"; dotfiles_managed_endpoint; } \
    && [ "${DOTFILES_ALLOW_PUBLISHER_NA_PYTHON:-0}" != "1" ]; then
  export AGENTBREW_MCPM_BIN=/nonexistent/dotfiles-mcpm-disabled-by-endpoint-policy
  echo "○ agentbrew mcpm bridge disabled (endpoint-policy safe mode)"
fi

# Stable ~/.config/dotfiles/hooks paths must exist before agentbrew sync writes
# agent hook entries that reference them.
if [ -x "$DOTFILES_DIR/.chezmoiscripts/run_after_agent-hooks.sh" ]; then
  bash "$DOTFILES_DIR/.chezmoiscripts/run_after_agent-hooks.sh" || true
fi

AGENTFILE="$DOTFILES_DIR/Agentfile.yaml"

# Locate the agentbrew checkout — handles both ~/apps/agentbrew (historical)
# and ~/apps/tooling/agentbrew (current monorepo-tooling layout). Same probe
# as the zshrc agentbrew shell function.
# shellcheck source=../lib/agentbrew-locate.sh
source "$DOTFILES_DIR/lib/agentbrew-locate.sh"
AGENTBREW_REPO="$(agentbrew_locate || true)"

# Resolve agentbrew command — shell function won't be available in bash chezmoi scripts.
# Prefer the built CLI (dist/cli.js — what package.json declares as `bin`) so the
# script works on machines that haven't run `npm install` yet; fall back to tsx
# + src/cli.ts for dev iteration on uncompiled checkouts.
if command -v agentbrew &>/dev/null; then
  AGENTBREW_CMD="agentbrew"
elif [ -n "$AGENTBREW_REPO" ] && [ -x "$AGENTBREW_REPO/dist/cli.js" ]; then
  AGENTBREW_CMD="node $AGENTBREW_REPO/dist/cli.js"
elif [ -n "$AGENTBREW_REPO" ] && [ -x "$AGENTBREW_REPO/node_modules/.bin/tsx" ]; then
  AGENTBREW_CMD="$AGENTBREW_REPO/node_modules/.bin/tsx $AGENTBREW_REPO/src/cli.ts"
else
  echo "○ agentbrew not available — skipping agent sync"
  exit 0
fi

# ── Company plugin Agentfiles ─────────────────────────────────────
# Verified plugins in plugins.lock add Agentfile layers through
# contributes.agentbrew (docs/plugins.md). The v1 overlay was removed;
# a leftover EXTRA_* setting stops here with one clear line.
PLUGIN_AGENTFILES=()
if [ -f "$DOTFILES_DIR/lib/plugin.sh" ]; then
  # shellcheck source=../lib/plugin.sh
  source "$DOTFILES_DIR/lib/plugin.sh"
  plugin_v1_guard || exit 1
fi
if [ -f "$DOTFILES_DIR/lib/plugin-extensions.sh" ] && command -v yq >/dev/null 2>&1; then
  for _plib in plugin-capabilities plugin-extensions; do
    # shellcheck source=/dev/null
    source "$DOTFILES_DIR/lib/$_plib.sh"
  done
  while IFS= read -r _pf; do
    [ -n "$_pf" ] && PLUGIN_AGENTFILES+=("$_pf") && echo "→ Including plugin Agentfile at $_pf"
  done < <(plugin_agentfiles)
fi

_agentbrew_supports_agentfile_merge() {
  local help
  help="$($AGENTBREW_CMD agentfile merge --help 2>&1 || true)"
  printf '%s\n' "$help" | grep -q 'agentbrew agentfile merge'
}

_sync_from_agentfile() {
  local agentfile="$1"
  shift
  if $AGENTBREW_CMD sync --no-recommended --agentfile "$agentfile" "$@" 2>&1; then
    echo "✓ agentbrew synced from Agentfile"
  else
    echo "⚠ agentbrew sync failed (non-fatal)"
  fi
}

AGENTFILE_PATHS=()
if [ -f "$AGENTFILE" ]; then
  AGENTFILE_PATHS+=("$AGENTFILE")
else
  echo "○ No Agentfile.yaml in dotfiles — skipping base agent sync"
fi
AGENTFILE_PATHS+=(${PLUGIN_AGENTFILES[@]+"${PLUGIN_AGENTFILES[@]}"})
# Owner-only rules and the local layer (lib/agentfile-layers.sh). The local
# layer is checked with the same agentbrew that merges it.
# shellcheck source=../lib/agentfile-layers.sh
source "$DOTFILES_DIR/lib/agentfile-layers.sh"
while IFS= read -r _layer; do
  [ -n "$_layer" ] && AGENTFILE_PATHS+=("$_layer")
done < <(AGENTFILE_AGENTBREW_CMD="$AGENTBREW_CMD" agentfile_optional_layers "$DOTFILES_DIR")

# This Mac's Claude model/effort, merged last (lib/claude-model-layer.sh).
# shellcheck source=../lib/claude-model-layer.sh
[ -f "$DOTFILES_DIR/lib/claude-model-layer.sh" ] && source "$DOTFILES_DIR/lib/claude-model-layer.sh"
if [ "${#AGENTFILE_PATHS[@]}" -gt 0 ]; then
  CLAUDE_MODEL_LAYER="$(mktemp "${TMPDIR:-/tmp}/dotfiles-claude-model.XXXXXX")"
  trap 'rm -f "$CLAUDE_MODEL_LAYER"' EXIT
  if declare -F claude_model_layer_write >/dev/null && claude_model_layer_write "$CLAUDE_MODEL_LAYER"; then
    AGENTFILE_PATHS+=("$CLAUDE_MODEL_LAYER")
  fi
fi

if [ "${#AGENTFILE_PATHS[@]}" -gt 0 ]; then
  GLOBAL_AGENTFILE="$HOME/.config/agentbrew/Agentfile.yaml"
  if _agentbrew_supports_agentfile_merge; then
    echo "→ Merging agentbrew Agentfiles into $GLOBAL_AGENTFILE..."
    if $AGENTBREW_CMD agentfile merge "${AGENTFILE_PATHS[@]}" --output "$GLOBAL_AGENTFILE" 2>&1; then
      echo "✓ canonical Agentfile updated"
      echo "→ Syncing agentbrew from canonical Agentfile..."
      _sync_from_agentfile "$GLOBAL_AGENTFILE"
    else
      echo "⚠ agentbrew Agentfile merge failed (non-fatal)"
    fi
  else
    echo "○ agentbrew Agentfile merge unavailable — using legacy sync"
    if [ -f "$AGENTFILE" ]; then
      echo "→ Syncing agentbrew from dotfiles Agentfile..."
      _sync_from_agentfile "$AGENTFILE"
    fi
    for _pf in ${PLUGIN_AGENTFILES[@]+"${PLUGIN_AGENTFILES[@]}"}; do
      echo "→ Syncing agentbrew from plugin Agentfile at $_pf..."
      _sync_from_agentfile "$_pf" --no-prune
    done
  fi
fi

# Jobs that sync just rewrote onto the approved agent Node can now be enabled,
# also when safe mode is off (the shim runs agentbrew on that Node anyway).
if $_agent_node_active || { [ -f "$DOTFILES_DIR/lib/dotfiles-agent-node.sh" ] \
    && source "$DOTFILES_DIR/lib/dotfiles-agent-node.sh" \
    && dotfiles_agent_node_bin >/dev/null; }; then
  PATH="$_default_node_path" "$DOTFILES_DIR/bin/dotfiles-disable-blocked-node-automation" || true
fi

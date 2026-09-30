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
if [ -f "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ] \
    && [ "${DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER:-0}" != "1" ]; then
  echo "○ agentbrew sync skipped: Node.js Foundation publisher is blocked (endpoint-policy safe mode)"
  exit 0
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
# ~/.cursor/hooks.json entries that reference them.
if [ -x "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-hooks.sh" ]; then
  bash "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-hooks.sh" || true
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

# ── Optional overlay Agentfile ────────────────────────────────────
# Organisation-specific overlays (a private repo at ~/apps/dotfiles-<org>/)
# can plug an additional Agentfile in via $EXTRA_AGENTFILE, OR a full
# overlay tree via $EXTRA_OVERLAY_ROOT (single-path) which auto-derives the
# Agentfile path as $EXTRA_OVERLAY_ROOT/Agentfile.yaml. Colon-separated
# $EXTRA_OVERLAY_ROOT is rejected — one overlay at a time.
# See docs/user-stories/10-fork-for-your-company.md.
# shellcheck source=../lib/overlay-locate.sh
source "$DOTFILES_DIR/lib/overlay-locate.sh"
EXTRA_AGENTFILE="${EXTRA_AGENTFILE:-}"
if [ -z "$EXTRA_AGENTFILE" ]; then
  _overlay_root="${EXTRA_OVERLAY_ROOT:-}"
  if [ -z "$_overlay_root" ]; then
    _overlay_root="$(overlay_locate || true)"
    if [ -n "$_overlay_root" ]; then
      echo "→ Auto-discovered overlay at $_overlay_root"
    fi
  fi
  if [ -n "$_overlay_root" ]; then
    if [[ "$_overlay_root" == *:* ]]; then
      echo "ERROR: EXTRA_OVERLAY_ROOT must be a single path, not colon-separated. One overlay at a time." >&2
      exit 1
    fi
    EXTRA_AGENTFILE="$_overlay_root/Agentfile.yaml"
  fi
fi
if [ -n "$EXTRA_AGENTFILE" ] && [ -f "$EXTRA_AGENTFILE" ]; then
  echo "→ Including overlay Agentfile at $EXTRA_AGENTFILE"
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
if [ -n "$EXTRA_AGENTFILE" ] && [ -f "$EXTRA_AGENTFILE" ]; then
  AGENTFILE_PATHS+=("$EXTRA_AGENTFILE")
fi
# use_cursor=false (chezmoi data, or DOTFILES_USE_CURSOR=false): exclude Cursor.
NO_CURSOR_AGENTFILE="$DOTFILES_DIR/config/agentfile-no-cursor.yaml"
if [ "${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}" = "false" ] \
    && [ -f "$NO_CURSOR_AGENTFILE" ]; then
  AGENTFILE_PATHS+=("$NO_CURSOR_AGENTFILE")
fi

if [ "${#AGENTFILE_PATHS[@]}" -gt 0 ]; then
  GLOBAL_AGENTFILE="$HOME/.config/agentbrew/Agentfile.yaml"
  if _agentbrew_supports_agentfile_merge; then
    echo "→ Merging agentbrew Agentfiles into $GLOBAL_AGENTFILE..."
    if $AGENTBREW_CMD agentfile merge "${AGENTFILE_PATHS[@]}" --output "$GLOBAL_AGENTFILE" 2>&1; then
      echo "✓ canonical Agentfile updated"
      echo "→ Syncing agentbrew from canonical Agentfile..."
      _sync_from_agentfile "$GLOBAL_AGENTFILE"
      if [ -x "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh" ]; then
        bash "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh" || true
      fi
    else
      echo "⚠ agentbrew Agentfile merge failed (non-fatal)"
    fi
  else
    echo "○ agentbrew Agentfile merge unavailable — using legacy sync"
    if [ -f "$AGENTFILE" ]; then
      echo "→ Syncing agentbrew from dotfiles Agentfile..."
      _sync_from_agentfile "$AGENTFILE"
    fi
    if [ -n "$EXTRA_AGENTFILE" ] && [ -f "$EXTRA_AGENTFILE" ]; then
      echo "→ Syncing agentbrew from overlay Agentfile at $EXTRA_AGENTFILE..."
      _sync_from_agentfile "$EXTRA_AGENTFILE" --no-prune
    fi
    if [ -x "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh" ]; then
      bash "$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh" || true
    fi
  fi
fi

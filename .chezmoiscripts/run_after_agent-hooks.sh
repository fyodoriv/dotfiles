#!/bin/bash
# Symlink dotfiles agent-hooks into ~/.config/dotfiles/hooks/ so the Agentfile
# hooks can reference stable paths regardless of dotfiles_dir layout.
set -euo pipefail

_resolve_dotfiles_dir() {
  local candidate
  if [ -n "${CHEZMOI_SOURCE_DIR:-}" ] && [ -d "$CHEZMOI_SOURCE_DIR/agent-hooks" ]; then
    printf '%s' "$CHEZMOI_SOURCE_DIR"
    return 0
  fi
  candidate="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  [ -n "$candidate" ] && [ -d "$candidate/agent-hooks" ] && { printf '%s' "$candidate"; return 0; }
  for candidate in \
    "${DOTFILES_DIR:-}" \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling/dotfiles" \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/dotfiles" \
    "$HOME/apps/tooling/dotfiles" \
    "$HOME/apps/dotfiles"; do
    [ -n "$candidate" ] && [ -d "$candidate/agent-hooks" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

DOTFILES_DIR="$(_resolve_dotfiles_dir || true)"
if [ -z "$DOTFILES_DIR" ]; then
  echo "○ Could not resolve dotfiles repo — skipping agent-hooks install" >&2
  exit 0
fi

HOOKS_DIR="${HOME}/.config/dotfiles/hooks"
mkdir -p "$HOOKS_DIR"

for hook in block-dangerous-git.sh bootstrap-endpoint-path.sh prepend-endpoint-path.sh session-endpoint-path.sh with-endpoint-path.sh; do
  src="$DOTFILES_DIR/agent-hooks/$hook"
  dest="$HOOKS_DIR/$hook"
  if [ ! -f "$src" ]; then
    echo "⚠ Missing agent hook source: $src" >&2
    continue
  fi
  ln -sf "$src" "$dest"
  chmod +x "$src" 2>/dev/null || true
done

echo "✓ agent-hooks linked in $HOOKS_DIR"


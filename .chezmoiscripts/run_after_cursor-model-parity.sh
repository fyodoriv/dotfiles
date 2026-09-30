#!/bin/bash
set -euo pipefail

# use_cursor=false (chezmoi data, or DOTFILES_USE_CURSOR=false) means no Cursor.
if [ "${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}" = "false" ]; then
  echo "○ Cursor disabled (use_cursor=false) — skipping $(basename "$0")"
  exit 0
fi

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

script_dir="$(cd "$(dirname "$0")" && pwd)"
for candidate in cursor-agent-parity.sh run_after_cursor-agent-parity.sh; do
  if [ -x "$script_dir/$candidate" ]; then
    exec "$script_dir/$candidate" "$@"
  fi
done

dotfiles_dir="$(_resolve_dotfiles_dir || true)"
if [ -n "$dotfiles_dir" ] && [ -x "$dotfiles_dir/.chezmoiscripts/run_after_cursor-agent-parity.sh" ]; then
  exec "$dotfiles_dir/.chezmoiscripts/run_after_cursor-agent-parity.sh" "$@"
fi

echo "cursor-model-parity: cursor agent parity script not found (checked $script_dir and dotfiles source)" >&2
exit 1

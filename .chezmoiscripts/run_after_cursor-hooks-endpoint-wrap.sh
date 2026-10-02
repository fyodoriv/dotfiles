#!/bin/bash
# Wrap Cursor hooks.json codeassist commands with with-endpoint-path.sh.
#
# Agentbrew sync rewrites ~/.cursor/hooks.json from Agentfile + managed hooks.
# Codeassist audit hooks (afterFileEdit, stop, postToolUse) run in sandbox PATH
# without dotfiles/bin — this script idempotently prepends the endpoint wrapper.
set -euo pipefail

# use_cursor=false (chezmoi data, or DOTFILES_USE_CURSOR=false) means no Cursor.
if [ "${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}" = "false" ]; then
  echo "○ Cursor disabled (use_cursor=false) — skipping $(basename "$0")"
  exit 0
fi

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
HOOKS_JSON="${HOME}/.cursor/hooks.json"
WRAPPER="${HOME}/.config/dotfiles/hooks/with-endpoint-path.sh"

if [ -z "$DOTFILES_DIR" ]; then
  echo "○ Could not resolve dotfiles repo — skipping hooks.json endpoint wrap" >&2
  exit 0
fi

if [ ! -f "$HOOKS_JSON" ]; then
  echo "○ No ~/.cursor/hooks.json — skipping endpoint wrap" >&2
  exit 0
fi

# Managed endpoint tooling can take ownership of hooks.json (for example as root).
# Its commands are then not ours to rewrite, and a failed write must not abort apply.
if [ ! -w "$HOOKS_JSON" ]; then
  echo "○ ~/.cursor/hooks.json is not writable (owner: $(stat -f %Su "$HOOKS_JSON" 2>/dev/null || echo unknown)) — managed by endpoint tooling; skipping endpoint wrap" >&2
  exit 0
fi

if [ ! -x "$WRAPPER" ]; then
  echo "⚠ Missing $WRAPPER — run run_after_cursor-agent-hooks.sh first" >&2
  exit 0
fi

changed=false
events="$(/usr/bin/plutil -extract hooks raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
while IFS= read -r event; do
  [ -n "$event" ] || continue
  count="$(/usr/bin/plutil -extract "hooks.$event" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || continue
  for ((index = 0; index < count; index++)); do
    key="hooks.$event.$index.command"
    command_value="$(/usr/bin/plutil -extract "$key" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
    [ -n "$command_value" ] || continue
    case "$command_value" in
      *prepend-endpoint-path*|*session-endpoint-path*|*bootstrap-endpoint-path*|*with-endpoint-path*|*block-dangerous-git*)
        continue
        ;;
    esac
    case "$command_value" in
      *hooks-scripts/*|*codeassist/*|*.claude/codeassist*|*.cursor/codeassist*)
        /usr/bin/plutil -replace "$key" -string "$WRAPPER $command_value" "$HOOKS_JSON"
        changed=true
        ;;
    esac
  done
done <<<"$events"

# Codeassist re-adds its unwrapped hook after each wrap, so every apply used to
# leave one more identical wrapped copy. Keep only the first copy.
removed=0
tab="$(printf '\t')"
while IFS= read -r event; do
  [ -n "$event" ] || continue
  count="$(/usr/bin/plutil -extract "hooks.$event" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
  [[ "$count" =~ ^[0-9]+$ ]] || continue
  seen=""
  index=0
  while [ "$index" -lt "$count" ]; do
    command_value="$(/usr/bin/plutil -extract "hooks.$event.$index.command" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
    matcher_value="$(/usr/bin/plutil -extract "hooks.$event.$index.matcher" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
    timeout_value="$(/usr/bin/plutil -extract "hooks.$event.$index.timeout" raw -o - "$HOOKS_JSON" 2>/dev/null || true)"
    signature="$matcher_value$tab$timeout_value$tab$command_value"
    if [ -n "$command_value" ] && printf '%s\n' "$seen" | grep -qxF -- "$signature"; then
      /usr/bin/plutil -remove "hooks.$event.$index" "$HOOKS_JSON"
      count=$((count - 1))
      removed=$((removed + 1))
      changed=true
      continue
    fi
    seen="$seen"$'\n'"$signature"
    index=$((index + 1))
  done
done <<<"$events"
[ "$removed" -eq 0 ] || echo "✓ Removed $removed duplicate hook entr$([ "$removed" -eq 1 ] && echo y || echo ies) from $HOOKS_JSON"

if $changed; then
  echo "✓ Wrapped codeassist hooks in $HOOKS_JSON with endpoint PATH bootstrap"
else
  echo "○ $HOOKS_JSON already has endpoint-safe hook wrappers"
fi

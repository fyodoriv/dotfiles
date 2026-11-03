#!/bin/bash
# Install the agentbrew Claude Code mods listed in the claude_mods setting.
#
# agentbrew ships optional mods (Claude Code plugins with a hooks module) in
# its mods/ folder, with a marketplace file there. This script registers that
# folder as the local "agentbrew-mods" marketplace and installs each listed
# mod through the claude CLI, so ~/.claude/settings.json is never edited by
# hand. The plugin reads straight from the checkout: a git pull updates it.
# Both claude commands are idempotent, so this runs on every apply.
#
# The list comes from the claude_mods setting (config/settings.yaml).
#   env:          DOTFILES_CLAUDE_MODS (comma list; set but empty = none)
#   chezmoi data: claude_mods (list)
# modules/claude/doctor.sh reads the resolved list with --print-list.
# Non-fatal: a missing claude CLI or agentbrew checkout skips with one line.
set -uo pipefail

# agentbrew retired work-pane (agentbrew #638); it ships no default mod now.
DEFAULT_LIST=""
MARKETPLACE="agentbrew-mods"

if [ -n "${DOTFILES_CLAUDE_MODS+x}" ]; then
  _list="$DOTFILES_CLAUDE_MODS"
else
  _list="$DEFAULT_LIST"
  if command -v chezmoi >/dev/null 2>&1; then
    _data="$(chezmoi execute-template '{{ $v := dig "claude_mods" "__unset__" . }}{{ if kindIs "slice" $v }}{{ join "," $v }}{{ else }}{{ $v }}{{ end }}' 2>/dev/null || echo __unset__)"
    [ "$_data" = "__unset__" ] || _list="$_data"
  fi
fi

# One mod name per line, blanks dropped.
MODS="$(printf '%s' "$_list" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')"
# agentbrew retired work-pane (#638): drop it from lists saved before that.
MODS="$(printf '%s\n' "$MODS" | grep -vx 'work-pane' | sed '/^$/d' || true)"

if [ "${1:-}" = "--print-list" ]; then
  [ -z "$MODS" ] || printf '%s\n' "$MODS"
  exit 0
fi

[ -n "$MODS" ] || exit 0
CLAUDE="$HOME/.local/bin/claude"
[ -x "$CLAUDE" ] || CLAUDE="$(command -v claude 2>/dev/null || true)"
[ -n "$CLAUDE" ] || { echo "· Claude Code mods skipped: no claude CLI"; exit 0; }

# The agentbrew checkout: AGENTBREW_DIR, then the usual layouts.
MODS_DIR=""
for _dir in "${AGENTBREW_DIR:-}" "${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling/agentbrew" "${DOTFILES_REPOS_DIR:-$HOME/apps}/agentbrew"; do
  [ -n "$_dir" ] && [ -f "$_dir/mods/.claude-plugin/marketplace.json" ] && { MODS_DIR="$_dir/mods"; break; }
done
[ -n "$MODS_DIR" ] || { echo "· Claude Code mods skipped: no agentbrew checkout with mods/"; exit 0; }

"$CLAUDE" plugin marketplace add "$MODS_DIR" >/dev/null 2>&1 || {
  echo "✗ Claude Code mods: could not add the $MARKETPLACE marketplace ($MODS_DIR)"
  exit 0
}
_ok=""
while IFS= read -r _mod; do
  if "$CLAUDE" plugin install "$_mod@$MARKETPLACE" >/dev/null 2>&1; then
    _ok="${_ok:+$_ok, }$_mod"
  else
    echo "✗ Claude Code mod $_mod did not install (is it in $MODS_DIR/.claude-plugin/marketplace.json?)"
  fi
done <<< "$MODS"
[ -z "$_ok" ] || echo "✓ Claude Code mods installed: $_ok"

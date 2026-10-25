#!/bin/bash
# Keep the listed Claude Code plugins turned off in ~/.claude/settings.json.
#
# Claude Code can turn an account-synced plugin back on by itself (the
# account plugin sync writes enabledPlugins["<name>@synced"] = true). This
# script sets each listed plugin to false on every `dotfiles apply`. It
# merges with jq and keeps every other key. Idempotent.
#
# The list comes from the claude_disabled_plugins setting (config/settings.yaml).
#   env:          DOTFILES_CLAUDE_DISABLED_PLUGINS (comma list; set but empty = none)
#   chezmoi data: claude_disabled_plugins (list)
# modules/claude/doctor.sh reads the resolved list with --print-list.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DEFAULT_LIST="prisma@synced"

if [ -n "${DOTFILES_CLAUDE_DISABLED_PLUGINS+x}" ]; then
  _list="$DOTFILES_CLAUDE_DISABLED_PLUGINS"
else
  _list="$DEFAULT_LIST"
  if command -v chezmoi >/dev/null 2>&1; then
    _data="$(chezmoi execute-template '{{ $v := dig "claude_disabled_plugins" "__unset__" . }}{{ if kindIs "slice" $v }}{{ join "," $v }}{{ else }}{{ $v }}{{ end }}' 2>/dev/null || echo __unset__)"
    [ "$_data" = "__unset__" ] || _list="$_data"
  fi
fi

# One plugin id per line, blanks dropped.
PLUGINS="$(printf '%s' "$_list" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d')"

if [ "${1:-}" = "--print-list" ]; then
  [ -z "$PLUGINS" ] || printf '%s\n' "$PLUGINS"
  exit 0
fi

[ -n "$PLUGINS" ] || exit 0
# Nothing to do on a Mac without Claude Code.
[ -e "$HOME/.local/bin/claude" ] || [ -s "$SETTINGS" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "✗ jq missing — cannot safely merge ~/.claude/settings.json (install jq via Brewfile)"
  exit 0
}

mkdir -p "$HOME/.claude"
[ -s "$SETTINGS" ] || echo '{}' > "$SETTINGS"

names_json="$(printf '%s\n' "$PLUGINS" | jq -R . | jq -sc .)"
# Already off: leave the file untouched.
if jq -e --argjson n "$names_json" '[$n[] as $p | .enabledPlugins[$p]] | all(. == false)' "$SETTINGS" >/dev/null 2>&1; then
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
jq --argjson n "$names_json" 'reduce $n[] as $p (.; .enabledPlugins[$p] = false)' "$SETTINGS" > "$TMP"
jq -e . "$TMP" >/dev/null 2>&1 || {
  echo "✗ jq produced invalid JSON — refusing to overwrite $SETTINGS"
  exit 1
}
mv "$TMP" "$SETTINGS"
echo "✓ Claude Code plugins kept off: $(printf '%s' "$PLUGINS" | paste -sd, -)"

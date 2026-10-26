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
# Follow a symlinked settings.json (dotfiles or agentbrew may link it), so the
# write lands in the real file and the link stays.
TARGET="$SETTINGS"
if [ -L "$SETTINGS" ]; then
  TARGET="$(cd "$(dirname "$SETTINGS")" && cd "$(dirname "$(readlink "$SETTINGS")")" && pwd)/$(basename "$(readlink "$SETTINGS")")"
fi

if [ -s "$TARGET" ]; then
  jq -e 'type == "object"' "$TARGET" >/dev/null 2>&1 || {
    echo "✗ $TARGET is not a JSON object — refusing to overwrite it" >&2
    exit 1
  }
  CURRENT="$(cat "$TARGET")"
else
  CURRENT="{}"
fi

names_json="$(printf '%s\n' "$PLUGINS" | jq -R . | jq -sc .)"
# Already off: leave the file untouched.
if printf '%s' "$CURRENT" | jq -e --argjson n "$names_json" '[$n[] as $p | .enabledPlugins[$p]] | all(. == false)' >/dev/null 2>&1; then
  exit 0
fi

# Temp file in the same folder, so mv is an atomic rename on one filesystem.
TMP="$(mktemp "$(dirname "$TARGET")/.settings.json.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$CURRENT" | jq --argjson n "$names_json" 'reduce $n[] as $p (.; .enabledPlugins[$p] = false)' > "$TMP"
jq -e 'type == "object"' "$TMP" >/dev/null 2>&1 || {
  echo "✗ jq produced invalid JSON — refusing to overwrite $TARGET" >&2
  exit 1
}
if [ -e "$TARGET" ]; then
  chmod "$(stat -f '%Lp' "$TARGET" 2>/dev/null || stat -c '%a' "$TARGET")" "$TMP"
else
  chmod 600 "$TMP"
fi
mv "$TMP" "$TARGET"
echo "✓ Claude Code plugins kept off: $(printf '%s' "$PLUGINS" | paste -sd, -)"

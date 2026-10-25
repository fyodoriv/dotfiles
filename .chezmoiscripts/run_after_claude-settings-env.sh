#!/bin/bash
# Pin Claude Code env values in ~/.claude/settings.json (the "env" object).
#
# AGENT_GUARD_DEPTH_MAX=2 lets the agent-usage-guard plugin (installed by
# agentbrew) allow one more level of nested subagents than its default of 1.
# Owner choice 2026-10-25: "depth 2".
#
# Claude Code owns settings.json and writes other keys into it, so this script
# merges only the keys below with jq and keeps every other field. Runs after
# every chezmoi apply. Idempotent.
set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
DESIRED_ENV='{"AGENT_GUARD_DEPTH_MAX":"2"}'

if [ "${1:-}" = "--print-desired" ]; then
  printf '%s\n' "$DESIRED_ENV"
  exit 0
fi

# Skip if Claude Code isn't installed.
[ -e "$HOME/.local/bin/claude" ] || exit 0
command -v jq >/dev/null 2>&1 || {
  echo "✗ jq missing — cannot safely merge ~/.claude/settings.json env"
  exit 0
}

mkdir -p "$HOME/.claude"
if [ -s "$SETTINGS" ]; then CURRENT="$(cat "$SETTINGS")"; else CURRENT="{}"; fi

if printf '%s' "$CURRENT" | jq -e --argjson want "$DESIRED_ENV" \
  '(.env // {}) as $e | all($want | to_entries[]; $e[.key] == .value)' >/dev/null 2>&1; then
  exit 0
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$CURRENT" | jq --argjson want "$DESIRED_ENV" '.env = ((.env // {}) + $want)' > "$TMP"
jq -e . "$TMP" >/dev/null 2>&1 || {
  echo "✗ jq produced invalid JSON — refusing to overwrite $SETTINGS"
  exit 1
}
mv "$TMP" "$SETTINGS"
echo "✓ Claude Code settings.json env pinned: AGENT_GUARD_DEPTH_MAX=2"

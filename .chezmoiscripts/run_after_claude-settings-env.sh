#!/bin/bash
# Pin Claude Code env values in ~/.claude/settings.json (the "env" object).
#
# AGENT_GUARD_DEPTH_MAX=2 lets the agent-usage-guard plugin (installed by
# agentbrew) allow nested subagents up to depth 2 instead of its default
# depth 1. Owner choice 2026-10-25.
#
# Claude Code owns settings.json and writes other keys into it, so this script
# merges only the keys below with jq and keeps every other field. It writes
# through a symlink to its real target and keeps the file mode. Runs after
# every chezmoi apply. Idempotent. modules/claude/doctor.sh reads
# --print-desired to warn on drift.
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
# Write through a symlink: edit its real target, not the link.
TARGET="$SETTINGS"
if [ -L "$SETTINGS" ]; then
  TARGET="$(cd "$(dirname "$SETTINGS")" && cd "$(dirname "$(readlink "$SETTINGS")")" && pwd)/$(basename "$(readlink "$SETTINGS")")"
fi

if [ -s "$TARGET" ]; then
  jq -e 'type == "object"' "$TARGET" >/dev/null 2>&1 || {
    echo "✗ $TARGET is not valid JSON — refusing to overwrite it" >&2
    exit 1
  }
  CURRENT="$(cat "$TARGET")"
else
  CURRENT="{}"
fi

if printf '%s' "$CURRENT" | jq -e --argjson want "$DESIRED_ENV" \
  '(.env // {}) as $e | all($want | to_entries[]; $e[.key] == .value)' >/dev/null 2>&1; then
  exit 0
fi

# Temp file in the same folder, so mv is an atomic rename on one filesystem.
TMP="$(mktemp "$(dirname "$TARGET")/.settings.json.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$CURRENT" | jq --argjson want "$DESIRED_ENV" '.env = ((.env // {}) + $want)' > "$TMP"
jq -e . "$TMP" >/dev/null 2>&1 || {
  echo "✗ jq produced invalid JSON — refusing to overwrite $TARGET" >&2
  exit 1
}
if [ -e "$TARGET" ]; then
  chmod "$(stat -f '%Lp' "$TARGET" 2>/dev/null || stat -c '%a' "$TARGET")" "$TMP"
else
  chmod 600 "$TMP"
fi
mv "$TMP" "$TARGET"
echo "✓ Claude Code settings.json env pinned: AGENT_GUARD_DEPTH_MAX=2"

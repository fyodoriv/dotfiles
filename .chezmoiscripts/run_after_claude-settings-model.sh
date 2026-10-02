#!/bin/bash
# Pin Claude Code's default model and permission mode in ~/.claude/settings.json.
#
# Per AGENTS.md § Model Configuration, Claude Code's tier-1 default is
# "Claude Opus 5.5 Medium" — which Claude Code expresses as:
#   - model:       "claude-opus-5-5"   (rejects effort suffixes such as -max)
#   - effortLevel: "medium"            (persistable: low/medium/high/xhigh; max is in-session only)
#
# Keep these values equal to defaultModel/defaultEffort in Agentfile.yaml.
# agentbrew writes the same keys; this pin covers machines where agentbrew
# cannot run (tests/claude-model-agentfile-consistency.bats).
#
# ~/.claude/settings.json is owned by Claude Code itself — it writes hooks,
# MCPs, plugins, etc. into the same file. We use `jq` to merge in just the
# model/permission keys, preserving every other field. Runs after every chezmoi
# apply. Idempotent.
#
# The ~/bin/claude wrapper installed by run_after_claude-wrapper.sh strips
# ANTHROPIC_MODEL env leaks (different concern); this script is the
# config-file source of truth for which model Claude Code launches with.
set -euo pipefail

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || true)"
if [ -f "$_script_dir/lib/dotfiles-endpoint-paths.sh" ]; then
  # shellcheck source=../lib/dotfiles-endpoint-paths.sh
  source "$_script_dir/lib/dotfiles-endpoint-paths.sh"
  dotfiles_prepend_endpoint_tool_paths "$_script_dir/bin"
fi
unset _script_dir

SETTINGS="$HOME/.claude/settings.json"
DESIRED_MODEL="claude-opus-5-5"
DESIRED_EFFORT="medium"
DESIRED_PERMISSION_MODE="bypassPermissions"

# Skip if Claude Code isn't installed (no ~/.local/bin/claude binary).
[ -e "$HOME/.local/bin/claude" ] || exit 0

# Skip if jq isn't available — better to no-op than to corrupt the file.
command -v jq >/dev/null 2>&1 || {
  echo "✗ jq missing — cannot safely merge ~/.claude/settings.json (install jq via Brewfile)"
  exit 0
}

mkdir -p "$HOME/.claude"

# Read current state, defaulting to {} if file missing/empty.
if [ -s "$SETTINGS" ]; then
  CURRENT="$(cat "$SETTINGS")"
else
  CURRENT="{}"
fi

_sync_claude_mcp_permissions() {
  local claude_json="$HOME/.claude.json"
  [ -f "$claude_json" ] || return 0
  local perm_tmp merged current_allow
  current_allow="$(jq -c '.permissions.allow // []' "$SETTINGS")"
  merged="$(jq -c --slurpfile cj "$claude_json" '
    ($cj[0].mcpServers // {}) as $servers |
    ($servers | keys | map("mcp__" + . + "__*")) as $desired |
    (.permissions.allow // [] | map(select(test("^mcp__") | not))) as $non_mcp |
    ($desired + $non_mcp | unique) as $merged |
    $merged
  ' "$SETTINGS")"
  [ "$current_allow" = "$merged" ] && return 0
  perm_tmp="$(mktemp)"
  jq --slurpfile cj "$claude_json" '
    ($cj[0].mcpServers // {}) as $servers |
    ($servers | keys | map("mcp__" + . + "__*")) as $desired |
    (.permissions.allow // [] | map(select(test("^mcp__") | not))) as $non_mcp |
    ($desired + $non_mcp | unique) as $merged |
    .permissions = ((.permissions // {}) + {allow: $merged})
  ' "$SETTINGS" > "$perm_tmp"
  jq -e . "$perm_tmp" >/dev/null 2>&1 || {
    echo "✗ jq produced invalid JSON — refusing to merge MCP permissions into $SETTINGS"
    rm -f "$perm_tmp"
    exit 1
  }
  mv "$perm_tmp" "$SETTINGS"
  echo "✓ Claude Code MCP permission grants synced from ~/.claude.json"
}

# Check if model pin already correct — skip model write but still sync MCP grants.
CURRENT_MODEL="$(printf '%s' "$CURRENT" | jq -r '.model // ""')"
CURRENT_EFFORT="$(printf '%s' "$CURRENT" | jq -r '.effortLevel // ""')"
CURRENT_PERMISSION_MODE="$(printf '%s' "$CURRENT" | jq -r '.permissions.defaultMode // ""')"
CURRENT_SKIP_AUTO_PROMPT="$(printf '%s' "$CURRENT" | jq -r '.skipAutoPermissionPrompt // false')"
if [ "$CURRENT_MODEL" = "$DESIRED_MODEL" ] \
  && [ "$CURRENT_EFFORT" = "$DESIRED_EFFORT" ] \
  && [ "$CURRENT_PERMISSION_MODE" = "$DESIRED_PERMISSION_MODE" ] \
  && [ "$CURRENT_SKIP_AUTO_PROMPT" = "true" ]; then
  _sync_claude_mcp_permissions
  exit 0
fi

# Merge: set model and permission defaults, preserve everything else.
# `--arg` for safe string interpolation. Atomic write via tmp file.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf '%s' "$CURRENT" \
  | jq --arg model "$DESIRED_MODEL" --arg effort "$DESIRED_EFFORT" --arg permissionMode "$DESIRED_PERMISSION_MODE" \
       '.model = $model | .effortLevel = $effort | .permissions.defaultMode = $permissionMode | .skipAutoPermissionPrompt = true' \
  > "$TMP"

# Sanity-check the result parses as JSON before installing.
jq -e . "$TMP" >/dev/null 2>&1 || {
  echo "✗ jq produced invalid JSON — refusing to overwrite $SETTINGS"
  exit 1
}

mv "$TMP" "$SETTINGS"
echo "✓ Claude Code settings.json pinned: model=$DESIRED_MODEL, effortLevel=$DESIRED_EFFORT, permissionMode=$DESIRED_PERMISSION_MODE"

_sync_claude_mcp_permissions

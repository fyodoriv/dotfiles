#!/bin/bash
# Doctor checks for claude module — Claude Code CLI (claude.ai/code).
# Agent config (MCP, skills, rules) is managed by agentbrew — see modules/agentbrew/.

# ── Claude CLI wrapper ────────────────────────────────────────────────
# A wrapper at ~/bin/claude strips any leaked ANTHROPIC_MODEL before exec and
# starts Claude Code with bypassPermissions by default. For Remote Control
# it puts that flag after the verb, which `claude rc` requires.
# Lives in ~/bin/ (not ~/.local/bin/) so claude update cannot overwrite it.
check "claude.model_wrapper" "\$HOME/bin/claude strips ANTHROPIC_MODEL and defaults permission mode" \
  "[ -f \"\$HOME/bin/claude\" ] && grep -q 'unset ANTHROPIC_MODEL' \"\$HOME/bin/claude\" && grep -q 'default-permission-mode-bypass' \"\$HOME/bin/claude\" && grep -q 'remote-control-flags-after-verb' \"\$HOME/bin/claude\"" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-wrapper.sh'"

# ── Claude Code model default ─────────────────────────────────────────
# Per AGENTS.md § Model Configuration, Claude Code's tier-1 default is
# "Claude Opus 5.5 XHigh" — model="claude-opus-5-5" + effortLevel="xhigh"
# in ~/.claude/settings.json. The pin is installed idempotently by
# .chezmoiscripts/run_after_claude-settings-model.sh on every chezmoi apply.
# That script also resolves per-machine overrides, so this check asks it for
# the expected pair (--print-desired) instead of keeping its own copy.
# We check via jq if available (the script requires it anyway); fall back
# to a grep that tolerates ordering/spacing if jq is somehow absent.
_claude_model_is_default() {
  local settings="$HOME/.claude/settings.json"
  [ -s "$settings" ] || return 1
  local want_m want_e want_p
  read -r want_m want_e < <(bash "$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-model.sh" --print-desired 2>/dev/null) || return 1
  [ -n "$want_m" ] && [ -n "$want_e" ] || return 1
  # claude_permissions: keep → only model and effort are dotfiles' to check.
  want_p="$(bash "$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-model.sh" --print-permissions 2>/dev/null || echo manage)"
  if command -v jq >/dev/null 2>&1; then
    local m e p s
    m="$(jq -r '.model // ""' "$settings" 2>/dev/null)"
    e="$(jq -r '.effortLevel // ""' "$settings" 2>/dev/null)"
    p="$(jq -r '.permissions.defaultMode // ""' "$settings" 2>/dev/null)"
    s="$(jq -r '.skipAutoPermissionPrompt // false' "$settings" 2>/dev/null)"
    [ "$m" = "$want_m" ] && [ "$e" = "$want_e" ] || return 1
    [ "$want_p" = "keep" ] && return 0
    [ "$p" = "bypassPermissions" ] && [ "$s" = "true" ]
  else
    # Escape the model for grep: an id such as claude-opus-5-5[1m] has brackets.
    local want_m_re
    want_m_re="$(printf '%s' "$want_m" | sed 's/[][\\.*^$]/\\&/g')"
    grep -q "\"model\"[[:space:]]*:[[:space:]]*\"$want_m_re\"" "$settings" && \
      grep -q "\"effortLevel\"[[:space:]]*:[[:space:]]*\"$want_e\"" "$settings" || return 1
    [ "$want_p" = "keep" ] && return 0
    grep -q '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"' "$settings" && \
      grep -q '"skipAutoPermissionPrompt"[[:space:]]*:[[:space:]]*true' "$settings"
  fi
}
check "claude.model_default" "Claude Code config pinned to Opus 5.5 xhigh (or this machine's override) and bypassPermissions" \
  "_claude_model_is_default" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-model.sh'"

# Env pins (AGENT_GUARD_DEPTH_MAX=2: agent-usage-guard allows depth 2). The
# expected values come from the fix script's --print-desired, so the check
# and the fix never disagree.
_claude_env_pinned() {
  local settings="$HOME/.claude/settings.json" want
  [ -s "$settings" ] && command -v jq >/dev/null 2>&1 || return 1
  want="$(bash "$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-env.sh" --print-desired 2>/dev/null)" || return 1
  jq -e --argjson want "$want" '(.env // {}) as $e | all($want | to_entries[]; $e[.key] == .value)' "$settings" >/dev/null 2>&1
}
check "claude.env_pins" "Claude Code env pins set (AGENT_GUARD_DEPTH_MAX=2: agent-usage-guard allows depth 2)" \
  "_claude_env_pinned" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-env.sh'"

# ── agents-observe plugin server ──────────────────────────────────────
# The agents-observe plugin hooks every Claude Code event but sends all
# errors to /dev/null. Its hook starts the Docker server on demand, and the
# server stops itself when no session is connected, so a stopped server is
# normal. A dead Docker engine is not: the plugin then records nothing and
# says nothing. This check makes that state visible.
_claude_observe_plugin_ok() {
  local settings="$HOME/.claude/settings.json"
  [ -s "$settings" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ "$(jq -r '.enabledPlugins["agents-observe@agents-observe"] // false' "$settings" 2>/dev/null)" = "true" ] || return 0
  curl -fsS --max-time 2 "http://127.0.0.1:${AGENTS_OBSERVE_SERVER_PORT:-4981}/api/health" >/dev/null 2>&1 && return 0
  curl -fsS --max-time 3 --unix-socket "$HOME/.rd/docker.sock" http://localhost/_ping >/dev/null 2>&1
}
check "claude.observe_plugin_server" "agents-observe plugin can start its server (Docker API answers; opt out: claude plugin disable agents-observe@agents-observe)" \
  "_claude_observe_plugin_ok" \
  "bash '$DOTFILES_DIR/bin/rancher-desktop'"

# ── Plugins kept off ──────────────────────────────────────────────────
# The account plugin sync can turn a synced plugin back on. On every apply,
# .chezmoiscripts/run_after_claude-disabled-plugins.sh sets each plugin in
# claude_disabled_plugins (config/settings.yaml) to false. These checks find
# the plugin back on in Claude Code.
_claude_disabled_plugins_list() {
  bash "$DOTFILES_DIR/.chezmoiscripts/run_after_claude-disabled-plugins.sh" --print-list 2>/dev/null
}
_claude_disabled_plugins_off() {
  local settings="$HOME/.claude/settings.json" p
  [ -s "$settings" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$(jq -r --arg p "$p" '.enabledPlugins[$p] // false' "$settings" 2>/dev/null)" = "true" ] && return 1
  done < <(_claude_disabled_plugins_list)
  return 0
}
check "claude.disabled_plugins" "Claude Code plugins in claude_disabled_plugins are off in ~/.claude/settings.json" \
  "_claude_disabled_plugins_off" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-disabled-plugins.sh'"

# ── Declined MCP servers stay out ─────────────────────────────────────
# agentbrew lists context7 in declinedMcpServers. This check fails when an
# agent config still has it as an MCP server key.
_claude_context7_files() {
  printf '%s\n' \
    "$HOME/.claude.json" \
    "$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
    "$HOME/.config/opencode/opencode.json" \
    "$HOME/.local/share/dotfiles-vscode/settings.generated.json"
}
_claude_context7_found_in() {
  local f
  while IFS= read -r f; do
    [ -s "$f" ] || continue
    command -v jq >/dev/null 2>&1 || continue
    jq -e '[paths | select(length >= 2 and .[-1] == "context7" and ((.[-2] | tostring) | test("^(mcpServers|servers|mcp)$")))] | length > 0' "$f" >/dev/null 2>&1 \
      && printf '%s\n' "$f"
  done < <(_claude_context7_files)
  local codex="$HOME/.codex/config.toml"
  [ -f "$codex" ] && grep -qE '^[[:space:]]*\[mcp_servers\."?context7"?(\]|\.)' "$codex" && printf '%s\n' "$codex"
  return 0
}
# Scan once; the check reads the saved result.
_claude_context7_hits="$(_claude_context7_found_in | paste -sd, - | sed 's/,/, /g')"
_claude_context7_desc="No agent config lists the declined context7 MCP server"
[ -z "$_claude_context7_hits" ] || _claude_context7_desc="context7 MCP server found in $_claude_context7_hits (declined in agentbrew); remove that entry, then run agentbrew sync"
check "claude.no_context7_mcp" "$_claude_context7_desc" \
  "[ -z \"$_claude_context7_hits\" ]" \
  ""
unset _claude_context7_desc _claude_context7_hits

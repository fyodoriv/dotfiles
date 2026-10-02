#!/bin/bash
# Doctor checks for claude module — Claude Code CLI (claude.ai/code).
# Agent config (MCP, skills, rules) is managed by agentbrew — see modules/agentbrew/.

# ── Claude CLI wrapper ────────────────────────────────────────────────
# A wrapper at ~/bin/claude strips any leaked ANTHROPIC_MODEL before exec and
# starts Claude Code with bypassPermissions by default.
# Lives in ~/bin/ (not ~/.local/bin/) so claude update cannot overwrite it.
check "claude.model_wrapper" "\$HOME/bin/claude strips ANTHROPIC_MODEL and defaults permission mode" \
  "[ -f \"\$HOME/bin/claude\" ] && grep -q 'unset ANTHROPIC_MODEL' \"\$HOME/bin/claude\" && grep -q 'default-permission-mode-bypass' \"\$HOME/bin/claude\"" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-wrapper.sh'"

# ── Claude Code model default ─────────────────────────────────────────
# Per AGENTS.md § Model Configuration, Claude Code's tier-1 default is
# "Claude Opus 5.5 Medium" — model="claude-opus-5-5" + effortLevel="medium"
# in ~/.claude/settings.json. The pin is installed idempotently by
# .chezmoiscripts/run_after_claude-settings-model.sh on every chezmoi apply.
# We check via jq if available (the script requires it anyway); fall back
# to a grep that tolerates ordering/spacing if jq is somehow absent.
_claude_model_is_default() {
  local settings="$HOME/.claude/settings.json"
  [ -s "$settings" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    local m e p s
    m="$(jq -r '.model // ""' "$settings" 2>/dev/null)"
    e="$(jq -r '.effortLevel // ""' "$settings" 2>/dev/null)"
    p="$(jq -r '.permissions.defaultMode // ""' "$settings" 2>/dev/null)"
    s="$(jq -r '.skipAutoPermissionPrompt // false' "$settings" 2>/dev/null)"
    [ "$m" = "claude-opus-5-5" ] && [ "$e" = "medium" ] && [ "$p" = "bypassPermissions" ] && [ "$s" = "true" ]
  else
    grep -q '"model"[[:space:]]*:[[:space:]]*"claude-opus-5-5"' "$settings" && \
      grep -q '"effortLevel"[[:space:]]*:[[:space:]]*"medium"' "$settings" && \
      grep -q '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"' "$settings" && \
      grep -q '"skipAutoPermissionPrompt"[[:space:]]*:[[:space:]]*true' "$settings"
  fi
}
check "claude.model_default" "Claude Code config pinned to Opus 5.5 medium and bypassPermissions" \
  "_claude_model_is_default" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-model.sh'"

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

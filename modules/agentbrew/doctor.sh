#!/bin/bash
# Doctor checks for agentbrew module
# Agent config (MCP, skills, rules) is managed by agentbrew, not dotfiles.
# These checks verify agentbrew is installed, the Agentfile exists, and state is in sync.

AGENTFILE="$DOTFILES_DIR/Agentfile.yaml"

_agentbrew_cli_available() {
  command -v agentbrew >/dev/null 2>&1
}
check "agentbrew.cli_available" "agentbrew CLI available" \
  "_agentbrew_cli_available" ""

check "agentbrew.agentfile_exists" "Agentfile.yaml in dotfiles" \
  "[ -f '$AGENTFILE' ]" ""

check "agentbrew.initialized" "agentbrew state initialized" \
  "[ -f '$HOME/.config/agentbrew/state.yaml' ]" \
  "agentbrew init"

check "agentbrew.global_agentfile" "global Agentfile exists" \
  "[ -f '$HOME/.config/agentbrew/Agentfile.yaml' ] || [ -f '$HOME/.config/agentbrew/Agentfile' ]" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_agentbrew-sync.sh'"

_agentbrew_global_agentfile_in_sync() {
  command -v agentbrew >/dev/null 2>&1 || return 0
  local merge_help
  merge_help="$(agentbrew agentfile merge --help 2>&1 || true)"
  printf '%s\n' "$merge_help" | grep -q 'agentbrew agentfile merge' || return 0

  local global_agentfile="$HOME/.config/agentbrew/Agentfile.yaml"
  [ -f "$global_agentfile" ] || return 0

  local paths=()
  [ -f "$AGENTFILE" ] && paths+=("$AGENTFILE")

  local extra_agentfile="${EXTRA_AGENTFILE:-}"
  if [ -z "$extra_agentfile" ] && [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
    [[ "$EXTRA_OVERLAY_ROOT" == *:* ]] && return 1
    extra_agentfile="$EXTRA_OVERLAY_ROOT/Agentfile.yaml"
  fi
  if [ -z "$extra_agentfile" ] && [ -f "$DOTFILES_DIR/lib/overlay-locate.sh" ]; then
    # shellcheck source=../lib/overlay-locate.sh
    source "$DOTFILES_DIR/lib/overlay-locate.sh" 2>/dev/null || true
    local _overlay_root=""
    _overlay_root="$(overlay_locate 2>/dev/null || true)"
    if [ -n "$_overlay_root" ]; then
      [[ "$_overlay_root" == *:* ]] && return 1
      extra_agentfile="$_overlay_root/Agentfile.yaml"
    fi
  fi
  [ -n "$extra_agentfile" ] && [ -f "$extra_agentfile" ] && paths+=("$extra_agentfile")
  # Match run_after_agentbrew-sync.sh: use_cursor=false merges the no-Cursor Agentfile last.
  local no_cursor_agentfile="$DOTFILES_DIR/config/agentfile-no-cursor.yaml"
  if [ "${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}" = "false" ] \
      && [ -f "$no_cursor_agentfile" ]; then
    paths+=("$no_cursor_agentfile")
  fi
  [ "${#paths[@]}" -gt 0 ] || return 0

  local expected status
  expected="$(mktemp "${TMPDIR:-/tmp}/agentbrew-agentfile.XXXXXX")" || return 1
  if ! agentbrew agentfile merge "${paths[@]}" --output "$expected" >/dev/null 2>&1; then
    rm -f "$expected"
    return 1
  fi
  cmp -s "$expected" "$global_agentfile"
  status=$?
  rm -f "$expected"
  return "$status"
}

check "agentbrew.global_agentfile_in_sync" "global Agentfile matches dotfiles/overlay merge" \
  "_agentbrew_global_agentfile_in_sync" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_agentbrew-sync.sh'"

# ── MCP env vars — tokens needed by agentbrew-managed MCP servers ──
# These vars must be in ~/.zshenv.secrets so MCP servers can start cleanly.
# See home/zshenv.secrets.example for how to obtain each token.
_agentbrew_mcp_registered() {
  local server="$1"
  local state="$HOME/.config/agentbrew/state.yaml"
  [ -f "$state" ] || return 1
  awk -v name="$server" '
    /^[^[:space:]][^:]*:/ { in_mcp = ($0 ~ /^mcpServers:/) }
    in_mcp {
      line = $0
      gsub(/["'\''[:space:]]/, "", line)
      if (line == "-name:" name || line == "name:" name) found = 1
    }
    END { exit found ? 0 : 1 }
  ' "$state"
}

_check_env_for_mcp() {
  local server="$1" var_name="$2" desc="$3"
  local id_var
  id_var="$(printf '%s' "$var_name" | tr '[:upper:]' '[:lower:]')"
  if _agentbrew_mcp_registered "$server"; then
    check "agentbrew.env_${id_var}" "$desc" \
      "[ -n \"\${$var_name:-}\" ]" \
      "Run: agentbrew setup '$server' (or add 'export $var_name=...' to ~/.zshenv.secrets)"
  fi
}

_check_env_for_mcp "github" "GITHUB_TOKEN" "GITHUB_TOKEN set (needed by github MCP)"
_check_env_for_mcp "atlassian" "JIRA_URL" "JIRA_URL set (needed by atlassian MCP)"
_check_env_for_mcp "atlassian" "JIRA_USERNAME" "JIRA_USERNAME set (needed by atlassian MCP)"
_check_env_for_mcp "atlassian" "JIRA_API_TOKEN" "JIRA_API_TOKEN set (needed by atlassian MCP)"
_check_env_for_mcp "jenkins" "JENKINS_URL" "JENKINS_URL set (needed by jenkins MCP)"
_check_env_for_mcp "jenkins" "JENKINS_USER" "JENKINS_USER set (needed by jenkins MCP)"
_check_env_for_mcp "jenkins" "JENKINS_API_TOKEN" "JENKINS_API_TOKEN set (needed by jenkins MCP)"

# ── Generic env-var resolution gate ──────────────────────────────────
# Catches the entire class of "MCP server silently filtered out at sync time
# because its env var didn't resolve" regressions. agentbrew's drift output
# emits a `mcp-env-vars` entry per filtered server. This check is the runtime
# gate: if any registered server can't resolve its env vars via shell + macOS
# Keychain + gh-auth fallbacks, the doctor fails with the server name.
#
# History: 2026-05-21 — jira-mcp was silently filtered because
# `hasUnresolvedInheritedEnv` in agentbrew/mcp-sync.ts checked raw process.env
# instead of the broader `resolveEnvVar` (Keychain + alias fallback). The fix
# in agentbrew PR #1028 aligned the filter with the substitution path; this
# doctor check is the user-facing safety net that catches the same class of
# regression earlier.
# Implementation: parse `agentbrew status --json` with awk + grep, no python3
# dependency. JSON shape is stable: drift items appear as objects with a
# `"type":"mcp-env-vars"` field. We grep for that substring against the
# single-line JSON output; count = number of matches.
_agentbrew_mcp_env_drift_count() {
  command -v agentbrew >/dev/null 2>&1 || return 1
  local json
  json="$(agentbrew status --json 2>/dev/null)" || return 1
  [ -n "$json" ] || return 1
  # Squash newlines so each `{...}` object inside drift[] is searchable in one
  # pass. The mcp-env-vars marker is unambiguous; it only appears as a drift
  # item type.
  printf '%s' "$json" | tr -d '\n' | grep -o '"type":"mcp-env-vars"' | wc -l | tr -d ' '
}

_agentbrew_mcp_env_drift_names() {
  command -v agentbrew >/dev/null 2>&1 || return 1
  local json
  json="$(agentbrew status --json 2>/dev/null)" || return 1
  [ -n "$json" ] || return 1
  # Extract the `"agent":"<name>"` for each `"type":"mcp-env-vars"` drift item.
  # awk walks the squashed JSON, pairs the agent name with the next type and
  # emits the agent name when the type is mcp-env-vars.
  printf '%s' "$json" \
    | tr -d '\n' \
    | grep -oE '"agent":"[^"]+","type":"mcp-env-vars"' \
    | sed -E 's/"agent":"([^"]+)","type":"mcp-env-vars"/\1/' \
    | paste -sd ',' - \
    | sed 's/,/, /g'
}

_agentbrew_mcp_servers_ready() {
  # agentbrew CLI must be reachable. If not, fall back to the existing
  # `agentbrew.cli_available` check above — don't double-fail.
  command -v agentbrew >/dev/null 2>&1 || return 0
  local count
  count="$(_agentbrew_mcp_env_drift_count)"
  # No agentbrew --json output OR parse failure → treat as ready (don't
  # false-fail when status itself is broken; cli_available covers that).
  [ -z "$count" ] && return 0
  [ "$count" = "0" ]
}

if command -v agentbrew >/dev/null 2>&1; then
  # Compute description and failing names ONCE so we don't shell out to
  # `agentbrew status --json` twice per source. `|| true` swallows the
  # non-zero exit when agentbrew status itself fails — the `check` test
  # function then handles the "agentbrew broken" case via cli_available.
  _agentbrew_mcp_ready_failing_names="$(_agentbrew_mcp_env_drift_names 2>/dev/null || true)"
  if [ -n "$_agentbrew_mcp_ready_failing_names" ]; then
    _agentbrew_mcp_ready_desc="all registered MCP servers resolve their env vars (missing: $_agentbrew_mcp_ready_failing_names)"
  else
    _agentbrew_mcp_ready_desc="all registered MCP servers resolve their env vars"
  fi
  check "agentbrew.mcp_servers_ready" "$_agentbrew_mcp_ready_desc" \
    "_agentbrew_mcp_servers_ready" \
    "agentbrew setup  # configure missing env vars (or add to ~/.zshenv.secrets / macOS Keychain)"
fi

# ── Shared local memory MCP daemon ─────────────────────────────────
_agentbrew_use_ai_tools_enabled() {
  [ "$(chezmoi execute-template '{{ dig "use_ai_tools" false . }}' 2>/dev/null || echo "false")" = "true" ]
}

_agentbrew_memory_service_registered() {
  _agentbrew_mcp_registered "memory" || return 1
  grep -q 'http://127.0.0.1:18765/mcp' "$HOME/.config/agentbrew/state.yaml"
}

_agentbrew_memory_service_http_available() {
  # Keep this check on AgentBrew's canonical readiness contract. The CLI
  # performs initialize → notifications/initialized → tools/list and requires
  # a non-empty tool set, so dotfiles does not maintain a weaker curl-only
  # duplicate that can report a stale MCP host as healthy. The same doctor
  # process also checks Cursor, so use its shared single-flight result.
  # shellcheck source=../../lib/agentbrew-memory-readiness.sh
  source "$DOTFILES_DIR/lib/agentbrew-memory-readiness.sh"
  dotfiles_agentbrew_memory_doctor_ready
}

_agentbrew_memory_launchagent_identity() {
  local status_json expected_path
  expected_path="$HOME/Library/LaunchAgents/com.agentbrew.mcp-memory.plist"
  status_json="$(agentbrew memory status --json 2>/dev/null)" || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$status_json" |
      jq -e --arg expected_path "$expected_path" --arg expected_home "$HOME" '
        .launchAgentIdentity.loaded == true
        and .launchAgentIdentity.canonical == true
        and .launchAgentIdentity.path == $expected_path
        and .launchAgentIdentity.home == $expected_home
      ' >/dev/null
    return
  fi
  printf '%s\n' "$status_json" |
    grep -Fq "\"path\":\"$expected_path\"" &&
    grep -Fq "\"home\":\"$HOME\"" &&
    grep -Fq '"canonical":true'
}

_agentbrew_memory_service_singleton() {
  command -v ps >/dev/null 2>&1 || return 1
  local process_count
  process_count="$(
    ps -axo command= 2>/dev/null |
      awk '$1 ~ /\/python([0-9.]*)?$/ && $2 ~ /\/memory$/ && $3 == "server" { count++ } END { print count + 0 }'
  )"
  [ "$process_count" -le 1 ]
}

if _agentbrew_use_ai_tools_enabled && _agentbrew_memory_service_registered; then
  check_advisory "agentbrew.memory_service_http" "shared memory MCP discovery healthy (initialize + tools/list)" \
    "_agentbrew_memory_service_http_available" \
    "agentbrew memory fix"
  check "agentbrew.memory_launchagent_identity" \
    "memory LaunchAgent uses the canonical plist path and operator HOME" \
    "_agentbrew_memory_launchagent_identity" \
    "agentbrew memory fix"
  check_advisory "agentbrew.memory_service_singleton" "only one mcp-memory-service server process is running (stop per-chat stdio memory servers)" \
    "_agentbrew_memory_service_singleton" \
    "stop stale per-chat stdio memory servers, then run: agentbrew memory fix"
fi

# ── npm leftover — stale global npm install of claude-code ─────────
# The native installer is authoritative; the npm global install causes
# 'Multiple installations found' warnings in claude /doctor.
# Fix: npm -g uninstall @anthropic-ai/claude-code
_claude_npm_leftover() {
  local npm_bin
  npm_bin="$(npm -g bin 2>/dev/null)/claude"
  [ ! -f "$npm_bin" ] && return 0  # no npm global claude — clean
  local native_bin="$HOME/.local/bin/claude"
  # Leftover only if npm bin points to a different path than native
  [ "$npm_bin" = "$native_bin" ] && return 0
  return 1
}
check "agentbrew.claude_no_npm_leftover" "no stale npm global claude-code install" \
  "_claude_npm_leftover" \
  "npm -g uninstall @anthropic-ai/claude-code"

# ── Hook enforcement observation — deployed hooks still catch violations ──
# Reuses agentbrew's Phase-1 observation gate (scripts/hook-observation.sh)
# against the runtime decision log (~/.cache/agentbrew/hook-decisions.jsonl).
# Advisory, not a hard fail: warns when a hook RAN but never enforced over the
# last 7 days (ran-no-enforce). That's often benign (no violations occurred
# that week) but it's the closest deterministic signal that a hook's matcher /
# detection silently broke — worth a glance on an active multi-agent machine
# where most hooks normally enforce weekly. Skips cleanly when agentbrew, the
# script, or the log isn't present (e.g. the located checkout predates the
# script). The dotfiles-doctor auto-repair launchagent is the scheduler —
# it runs every interval and evaluates the trailing 7-day window. Investigate
# a warned hook with: "$(agentbrew_locate)/scripts/hook-observation.sh --since 7"
_agentbrew_hooks_enforcing() {
  local locate_lib="$DOTFILES_DIR/lib/agentbrew-locate.sh"
  [ -f "$locate_lib" ] || return 0
  # shellcheck source=/dev/null
  source "$locate_lib" 2>/dev/null || return 0
  local ab
  ab="$(agentbrew_locate 2>/dev/null)" || return 0
  local script="$ab/scripts/hook-observation.sh"
  [ -f "$script" ] || return 0
  [ -f "$HOME/.cache/agentbrew/hook-decisions.jsonl" ] || return 0
  bash "$script" --since 7 >/dev/null 2>&1
}
check_advisory "agentbrew.hooks_enforcing" \
  "deployed hooks still enforce — no ran-no-enforce hook in last 7d (else run hook-observation.sh --since 7)" \
  "_agentbrew_hooks_enforcing"

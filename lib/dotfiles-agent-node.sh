#!/bin/bash
# Opt-in agent Node for machines whose endpoint policy blocks the Node.js
# Foundation publisher (Team ID HX7739G8FX).
#
# DOTFILES_AGENT_NODE_BIN names a Node binary from another publisher, for
# example /opt/homebrew/bin/node. When it is set, executable, and not signed by
# the blocked publisher, agentbrew sync, its com.agentbrew.* LaunchAgents, and
# its doctors keep running on that Node. The default `node` and Topgrade safe
# mode do not change.
#
# Usage (sourced):
#   source "$DOTFILES_DIR/lib/dotfiles-agent-node.sh"
#   if agent_node="$(dotfiles_agent_node_bin)"; then ...; fi
#   dotfiles_enable_agent_node_jobs   # enable agent-Node jobs left disabled

DOTFILES_BLOCKED_NODE_TEAM_ID="HX7739G8FX"

# True when the binary is signed by the blocked Node.js Foundation publisher.
dotfiles_node_publisher_blocked() {
  local bin="${1:-}"
  [ -n "$bin" ] && [ -x "$bin" ] || return 1
  command -v codesign >/dev/null 2>&1 || return 1
  codesign -dvv "$bin" 2>&1 | grep -q "TeamIdentifier=$DOTFILES_BLOCKED_NODE_TEAM_ID"
}

# Print DOTFILES_AGENT_NODE_BIN when it is set, executable, and not blocked.
dotfiles_agent_node_bin() {
  local bin="${DOTFILES_AGENT_NODE_BIN:-}"
  [ -n "$bin" ] && [ -f "$bin" ] && [ -x "$bin" ] || return 1
  dotfiles_node_publisher_blocked "$bin" && return 1
  printf '%s\n' "$bin"
}

# Put the approved agent Node directory first on PATH for this process.
dotfiles_use_agent_node() {
  local bin
  bin="$(dotfiles_agent_node_bin)" || return 1
  PATH="$(dirname "$bin"):$PATH"
  export PATH
}

# True when a LaunchAgent plist would run the blocked Node: its program is the
# blocked binary, or the first `node` on its PATH is. A blocked bin later on
# PATH (for example fnm after the approved Node) never runs for a bare `node`.
dotfiles_launchagent_runs_blocked_node() {
  local plist="$1" program job_path entry
  program="$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$plist" 2>/dev/null \
    || /usr/bin/plutil -extract Program raw -o - "$plist" 2>/dev/null || true)"
  dotfiles_node_publisher_blocked "$program" && return 0
  job_path="$(/usr/bin/plutil -extract EnvironmentVariables.PATH raw -o - "$plist" 2>/dev/null || true)"
  IFS=':' read -r -a _agent_node_path_parts <<<"$job_path"
  for entry in "${_agent_node_path_parts[@]}"; do
    [ -n "$entry" ] && [ -x "$entry/node" ] || continue
    dotfiles_node_publisher_blocked "$entry/node"
    return
  done
  return 1
}

# True when launchd marks the gui-domain job disabled. Newer macOS prints
# `=> disabled`; older macOS prints `=> true`.
dotfiles_launchagent_disabled() {
  local label="$1" disabled
  disabled="$(launchctl print-disabled "gui/$(id -u)" 2>/dev/null)" || return 1
  grep -Fq -e "\"$label\" => disabled" -e "\"$label\" => true" <<<"$disabled"
}

# Print each com.agentbrew.* job that runs only the approved agent Node but is
# disabled in launchd, one label per line. Prints nothing without an agent
# Node. The uvx memory daemon is not Node-owned, so it is skipped.
dotfiles_agent_node_disabled_jobs() {
  local plist label
  dotfiles_agent_node_bin >/dev/null || return 0
  for plist in "$HOME"/Library/LaunchAgents/com.agentbrew.*.plist; do
    [ -f "$plist" ] || continue
    label="$(basename "$plist" .plist)"
    [ "$label" = "com.agentbrew.mcp-memory" ] && continue
    dotfiles_launchagent_runs_blocked_node "$plist" && continue
    dotfiles_launchagent_disabled "$label" && printf '%s\n' "$label"
  done
  return 0
}

# Enable each job that dotfiles_agent_node_disabled_jobs prints and report it.
# Safe mode can disable a job and then turn off; this runs either way, so the
# job does not stay off for good.
dotfiles_enable_agent_node_jobs() {
  local agent_node label
  agent_node="$(dotfiles_agent_node_bin)" || return 0
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    launchctl enable "gui/$(id -u)/$label" 2>/dev/null || true
    echo "✓ Re-enabled $label: it runs only the approved agent Node $agent_node"
  done < <(dotfiles_agent_node_disabled_jobs)
}

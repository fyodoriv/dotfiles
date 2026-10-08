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

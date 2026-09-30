#!/usr/bin/env bats

REPO_ROOT="$BATS_TEST_DIRNAME/.."
DAEMON_PLIST="$REPO_ROOT/launchagents/com.dotfiles.mcp-memory.plist.tmpl"
MAINTAIN_PLIST="$REPO_ROOT/launchagents/com.dotfiles.mcp-memory-maintain.plist.tmpl"
LAUNCHAGENT_SCRIPT="$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
RELOAD_SCRIPT="$REPO_ROOT/bin/dotfiles-reload-launchagents"

@test "legacy dotfiles memory LaunchAgents are disabled compatibility artifacts" {
  grep -A2 '<string>com.dotfiles.mcp-memory</string>' "$DAEMON_PLIST" | grep -q '<key>Disabled</key>'
  grep -A2 '<string>com.dotfiles.mcp-memory-maintain</string>' "$MAINTAIN_PLIST" | grep -q '<key>Disabled</key>'
  grep -A3 '<key>Disabled</key>' "$DAEMON_PLIST" | grep -q '<true/>'
  grep -A3 '<key>Disabled</key>' "$MAINTAIN_PLIST" | grep -q '<true/>'
}

@test "launchagent apply unloads and removes retired dotfiles memory agents" {
  grep -q 'for retired_label in com.dotfiles.mcp-memory com.dotfiles.mcp-memory-maintain' "$LAUNCHAGENT_SCRIPT"
  grep -q 'launchctl unload "$retired_plist"' "$LAUNCHAGENT_SCRIPT"
  grep -q 'rm -f "$retired_plist"' "$LAUNCHAGENT_SCRIPT"
  grep -A2 'mcp-memory|mcp-memory-maintain)' "$LAUNCHAGENT_SCRIPT" | grep -q 'return 0'
}

@test "manual reload no longer manages legacy dotfiles memory labels" {
  ! grep -q 'com.dotfiles.mcp-memory' "$RELOAD_SCRIPT"
}

@test "legacy daemon entrypoint refuses to start a second memory server" {
  run "$REPO_ROOT/bin/mcp-memory-launchagent"

  [ "$status" -eq 1 ]
  [[ "$output" == *"entrypoint is retired"* ]]
  [[ "$output" == *"agentbrew memory fix"* ]]
}

@test "Agentfile delegates memory lifecycle to agentbrew" {
  grep -A2 '^memory:' "$REPO_ROOT/Agentfile.yaml" | grep -q 'enabled: true'
  grep -q 'AgentBrew owns daemon, MCP URL, and pack reconciliation' "$REPO_ROOT/Agentfile.yaml"
}

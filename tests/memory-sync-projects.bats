#!/usr/bin/env bats
# Tests for the stable dotfiles compatibility entry point. AgentBrew owns the
# managed MCP client and project-memory implementation.

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$REPO_ROOT/bin/dotfiles-memory-sync-projects"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  AGENTBREW_LOG="$BATS_TEST_TMPDIR/agentbrew.log"
  export AGENTBREW_LOG
  cat <<'STUB' > "$STUB_BIN/agentbrew"
#!/bin/bash
printf '%s|%s|%s|%s\n' \
  "$*" \
  "${DOTFILES_CLAUDE_PROJECTS_DIR:-}" \
  "${DOTFILES_MEMORY_MCP_URL:-}" \
  "${DOTFILES_MEMORY_SYNC_TIMEOUT:-}" \
  >> "$AGENTBREW_LOG"
STUB
  chmod +x "$STUB_BIN/agentbrew"
  export DOTFILES_MEMORY_AGENTBREW_BIN="$STUB_BIN/agentbrew"
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "forwards sync arguments to AgentBrew" {
  run "$SCRIPT" --dry-run --quiet --json
  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --dry-run --quiet --json|||' "$AGENTBREW_LOG"
}

@test "forwards the compatibility project-memory environment aliases" {
  export DOTFILES_CLAUDE_PROJECTS_DIR="/tmp/claude-projects"
  export DOTFILES_MEMORY_MCP_URL="http://127.0.0.1:19876/mcp"
  export DOTFILES_MEMORY_SYNC_TIMEOUT="45"

  run "$SCRIPT" --check

  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --check|/tmp/claude-projects|http://127.0.0.1:19876/mcp|45' "$AGENTBREW_LOG"
}

@test "forwards help to the canonical command" {
  run "$SCRIPT" --help

  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --help|||' "$AGENTBREW_LOG"
}

@test "skips without blocking when AgentBrew is unavailable" {
  export DOTFILES_MEMORY_AGENTBREW_BIN="$STUB_BIN/missing-agentbrew"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"memory sync skipped: agentbrew is not available"* ]]
}

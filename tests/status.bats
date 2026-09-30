#!/usr/bin/env bats
# Tests for status — system health dashboard
# Note: does NOT load test_helper — these tests run against the real system

STATUS_CMD="$BATS_TEST_DIRNAME/../bin/status"
DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

# ── Script basics ────────────────────────────────────────────────

@test "status script exists and is executable" {
  [ -f "$STATUS_CMD" ]
  [ -x "$STATUS_CMD" ]
}

@test "status has correct shebang" {
  head -1 "$STATUS_CMD" | grep -q '#!/bin/bash'
}

@test "status uses strict mode" {
  grep -q 'set -euo pipefail' "$STATUS_CMD"
}

@test "status sources stats.sh" {
  grep -q 'source.*lib/stats.sh' "$STATUS_CMD"
}

# ── Section headers ──────────────────────────────────────────────

@test "status has Dotfiles section" {
  grep -q 'section "Dotfiles"' "$STATUS_CMD"
}

@test "status has Git section" {
  grep -q 'section "Git (current dir)"' "$STATUS_CMD"
}

@test "status has Agents section" {
  grep -q 'section "Agents"' "$STATUS_CMD"
}

@test "status has Ports section" {
  grep -q 'section "Ports in use"' "$STATUS_CMD"
}

# ── Dotfiles section ─────────────────────────────────────────────

@test "status shows dotfiles git version" {
  grep -q 'git rev-parse --short HEAD' "$STATUS_CMD"
}

@test "status shows dotfiles branch" {
  grep -q 'git rev-parse --abbrev-ref HEAD' "$STATUS_CMD"
}

@test "status shows last sync time" {
  grep -q 'git log -1 --format' "$STATUS_CMD"
}

@test "status shows module count" {
  grep -q 'fd -t d -d 1.*modules' "$STATUS_CMD"
}

@test "status shows time saved summary" {
  grep -q 'get_time_saved_summary' "$STATUS_CMD"
}

@test "status detects uncommitted dotfiles changes" {
  grep -q 'git status --porcelain' "$STATUS_CMD"
}

# ── Git section ──────────────────────────────────────────────────

@test "status checks if inside a git repo" {
  grep -q 'git rev-parse --is-inside-work-tree' "$STATUS_CMD"
}

@test "status shows message when not in a git repo" {
  grep -q 'Not in a git repo' "$STATUS_CMD"
}

@test "status shows ahead/behind counts" {
  grep -q 'rev-list --count' "$STATUS_CMD"
}

@test "status handles missing upstream gracefully" {
  # ahead/behind commands use || echo "?" fallback
  grep -q '|| echo "?"' "$STATUS_CMD"
}

# ── Fastfetch handling ───────────────────────────────────────────

@test "status checks for fastfetch availability" {
  grep -q 'command -v fastfetch' "$STATUS_CMD"
}

@test "status shows install hint when fastfetch is missing" {
  grep -q 'brew install fastfetch' "$STATUS_CMD"
}

@test "status falls back to sw_vers when fastfetch is missing" {
  grep -q 'sw_vers -productVersion' "$STATUS_CMD"
}

# ── LaunchAgents section ─────────────────────────────────────────

@test "status auto-discovers agents from launchagents directory" {
  grep -q 'launchagents/\*\.plist' "$STATUS_CMD"
}

@test "status strips com.dotfiles. prefix from agent names" {
  grep -q 'label#com.dotfiles.' "$STATUS_CMD"
}

@test "status uses launchctl to check agent status" {
  grep -q 'launchctl print' "$STATUS_CMD"
}

@test "status shows loaded vs not-loaded state for agents" {
  grep -q 'not loaded' "$STATUS_CMD"
}

# ── Ports section ────────────────────────────────────────────────

@test "status uses lsof to detect listening ports" {
  grep -q 'lsof -i -P -n' "$STATUS_CMD"
}

@test "status limits port output to 8 entries" {
  grep -q 'head -8' "$STATUS_CMD"
}

@test "status shows message when no ports are listening" {
  grep -q 'No listening ports' "$STATUS_CMD"
}

# ── Live output (hide fastfetch to avoid terminal control codes) ──

@test "status runs and exits 0" {
  cd "$DOTFILES_DIR"
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v fastfetch | tr '\n' ':') \
    run bash "$STATUS_CMD"
  [ "$status" -eq 0 ]
}

@test "status output contains Dotfiles section" {
  cd "$DOTFILES_DIR"
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v fastfetch | tr '\n' ':') \
    run bash "$STATUS_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dotfiles"* ]]
}

@test "status output contains module count" {
  cd "$DOTFILES_DIR"
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v fastfetch | tr '\n' ':') \
    run bash "$STATUS_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modules:"* ]]
  [[ "$output" == *"available"* ]]
}

@test "status outside git repo shows 'Not in a git repo'" {
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v fastfetch | tr '\n' ':') \
    run bash -c "cd /tmp && '$STATUS_CMD'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not in a git repo"* ]]
}

@test "status inside git repo shows branch info" {
  local tmpout
  tmpout=$(mktemp)
  bash -c "cd '$DOTFILES_DIR' && '$STATUS_CMD'" > "$tmpout" 2>&1
  grep -q 'Branch:' "$tmpout"
  rm -f "$tmpout"
}

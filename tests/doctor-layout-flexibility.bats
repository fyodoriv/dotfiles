#!/usr/bin/env bats
# Tests for layout-flexibility fixes in doctor modules and the agentbrew shim.
#
# The dotfiles assumed `${DOTFILES_REPOS_DIR:-$HOME/apps}/<repo>` everywhere,
# but several setups now use a `tooling/` wrapper directory
# (e.g. ~/apps/tooling/agentbrew). These tests pin the dual-path probing so
# both layouts work.

load test_helper

DOCTOR_AGENT_BROWSER="$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
DOCTOR_AGENTBREW="$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
DOCTOR_UPGRADE="$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"

@test "agentbrew_locate finds both apps/tooling/agentbrew and apps/agentbrew" {
  # The agentbrew launcher moved from zshrc.ai-tools into bin/agentbrew,
  # which resolves the checkout through lib/agentbrew-locate.sh.
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/tooling/agentbrew"
  run env DOTFILES_REPOS_DIR="$tmp" bash -c 'source "$1"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh"
  [ "$output" = "$tmp/tooling/agentbrew" ]
  rm -rf "$tmp/tooling"
  mkdir -p "$tmp/agentbrew"
  run env DOTFILES_REPOS_DIR="$tmp" bash -c 'source "$1"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh"
  [ "$output" = "$tmp/agentbrew" ]
  rm -rf "$tmp"
}

@test "bin/agentbrew prefers dist/cli.js over tsx" {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/agentbrew/dist" "$tmp/agentbrew/node_modules/.bin"
  printf '#!/bin/sh\necho dist\n' > "$tmp/agentbrew/dist/cli.js"
  printf '#!/bin/sh\necho tsx\n' > "$tmp/agentbrew/node_modules/.bin/tsx"
  chmod +x "$tmp/agentbrew/dist/cli.js" "$tmp/agentbrew/node_modules/.bin/tsx"
  run env DOTFILES_REPOS_DIR="$tmp" "$BATS_TEST_DIRNAME/../bin/agentbrew" --version
  [ "$output" = "dist" ]
  rm "$tmp/agentbrew/dist/cli.js"
  run env DOTFILES_REPOS_DIR="$tmp" "$BATS_TEST_DIRNAME/../bin/agentbrew" --version
  [ "$output" = "tsx" ]
  rm -rf "$tmp"
}

@test "agent-browser doctor checks both zshrc and zshrc.ai-tools for env vars" {
  # The previous check only looked at home/zshrc; AGENT_BROWSER_* exports
  # actually live in home/zshrc.ai-tools (opt-in via use_ai_tools).
  grep -A 1 'AGENT_BROWSER_IDLE_TIMEOUT_MS set' "$DOCTOR_AGENT_BROWSER" | grep -q 'zshrc.ai-tools'
  grep -A 1 'AGENT_BROWSER_DEFAULT_TIMEOUT configured' "$DOCTOR_AGENT_BROWSER" | grep -q 'zshrc.ai-tools'
}

@test "agentbrew doctor relies on the PATH shim that locates the checkout" {
  # bin/agentbrew is on PATH in every bash subshell, so the doctor's
  # `command -v agentbrew` check works for both layouts.
  grep -q '_agentbrew_cli_available' "$DOCTOR_AGENTBREW"
  grep -q 'agentbrew_locate' "$BATS_TEST_DIRNAME/../bin/agentbrew"
}

@test "upgrade doctor checks are gated behind auto_upgrade chezmoi data" {
  # When auto_upgrade is false (default), the lifecycle script refuses
  # to install the LaunchAgent; the doctor should likewise skip rather
  # than flag the missing agent as a failure.
  grep -q 'auto_upgrade' "$DOCTOR_UPGRADE"
  grep -q '_AUTO_UPGRADE_ENABLED' "$DOCTOR_UPGRADE"
  # Sanity: both checks live inside the gate, not outside it.
  awk '/_AUTO_UPGRADE_ENABLED.*=.*true/,/^fi$/' "$DOCTOR_UPGRADE" | grep -q 'upgrade.launchagent'
  awk '/_AUTO_UPGRADE_ENABLED.*=.*true/,/^fi$/' "$DOCTOR_UPGRADE" | grep -q 'upgrade.recent'
}

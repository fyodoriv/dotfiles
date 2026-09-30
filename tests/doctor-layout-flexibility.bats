#!/usr/bin/env bats
# Tests for layout-flexibility fixes in doctor modules and zshrc.ai-tools.
#
# The dotfiles assumed `${DOTFILES_REPOS_DIR:-$HOME/apps}/<repo>` everywhere,
# but several setups now use a `tooling/` wrapper directory
# (e.g. ~/apps/tooling/agentbrew). These tests pin the dual-path probing so
# both layouts work.

load test_helper

ZSHRC_AI="$BATS_TEST_DIRNAME/../home/zshrc.ai-tools"
DOCTOR_AGENT_BROWSER="$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
DOCTOR_AGENTBREW="$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
DOCTOR_DEVIN="$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
DOCTOR_UPGRADE="$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"

@test "zshrc.ai-tools probes both apps/ and apps/tooling/ for agentbrew" {
  # Two base paths declared and the agentbrew probe lists both.
  grep -q '_DOTFILES_BASE=' "$ZSHRC_AI"
  grep -q '_DOTFILES_TOOLING=' "$ZSHRC_AI"
  awk '/_agentbrew_dir=/,/^fi$/' "$ZSHRC_AI" | grep -q '_DOTFILES_BASE/agentbrew'
  awk '/_agentbrew_dir=/,/^fi$/' "$ZSHRC_AI" | grep -q '_DOTFILES_TOOLING/agentbrew'
}



@test "zshrc.ai-tools prefers dist/cli.js over tsx for agentbrew function" {
  awk '/_agentbrew_dir=/,/^fi$/' "$ZSHRC_AI" | grep -q 'dist/cli.js'
  awk '/_agentbrew_dir=/,/^fi$/' "$ZSHRC_AI" | grep -q 'node_modules/.bin/tsx'
}

@test "agent-browser doctor checks both zshrc and zshrc.ai-tools for env vars" {
  # The previous check only looked at home/zshrc; AGENT_BROWSER_* exports
  # actually live in home/zshrc.ai-tools (opt-in via use_ai_tools).
  grep -A 1 'AGENT_BROWSER_IDLE_TIMEOUT_MS set' "$DOCTOR_AGENT_BROWSER" | grep -q 'zshrc.ai-tools'
  grep -A 1 'AGENT_BROWSER_DEFAULT_TIMEOUT configured' "$DOCTOR_AGENT_BROWSER" | grep -q 'zshrc.ai-tools'
}

@test "agentbrew doctor falls back to function declaration + repo checkout" {
  # The `command -v agentbrew` test fails when the function lives in
  # zshrc.ai-tools but isn't exported into bash subshells. The doctor
  # must accept either path.
  grep -q '_agentbrew_cli_available' "$DOCTOR_AGENTBREW"
  grep -q 'agentbrew/dist/cli.js' "$DOCTOR_AGENTBREW"
  grep -q 'tooling/agentbrew' "$DOCTOR_AGENTBREW"
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

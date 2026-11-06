#!/usr/bin/env bats
# keep_awake_tools decides whether apply loads sleepwatcher and agent-keepawake,
# and whether the doctor checks them and Amphetamine. Default: full profile only.

load test_helper

TMPL="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_launchagents.sh.tmpl"

setup() {
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$TMPL")"
}

@test "keep_awake_tools=true loads sleepwatcher on any profile" {
  PROFILE=core KEEP_AWAKE_TOOLS=true
  command() { [ "$2" = "sleepwatcher" ] && return 0; builtin command "$@"; }
  run should_skip_agent sleepwatcher
  [ "$status" -eq 1 ]
}

@test "keep_awake_tools=false skips sleepwatcher, even on full" {
  PROFILE=full KEEP_AWAKE_TOOLS=false
  run should_skip_agent sleepwatcher
  [ "$status" -eq 0 ]
}

@test "launchagents template defaults keep_awake_tools to the full profile" {
  grep -q 'KEEP_AWAKE_TOOLS="{{ dig "keep_awake_tools" (eq .profile "full") . }}"' "$TMPL"
  grep -q 'KEEP_AWAKE_TOOLS="${DOTFILES_KEEP_AWAKE_TOOLS:-$(chezmoi execute-template '"'"'{{ dig "keep_awake_tools" (eq .profile "full") . }}'"'"'' "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
}

@test "chezmoi config keeps keep_awake_tools across chezmoi init" {
  grep -q 'hasKey . "keep_awake_tools"' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
  grep -q '^  keep_awake_tools: {{ \$keepAwakeTools }}' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
}

@test "doctor checks sleepwatcher and Amphetamine only when keep_awake_tools is on" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh"
  [ "$(grep -c 'if \[ "${KEEP_AWAKE_TOOLS:-true}" = "true" \]; then' "$DOCTOR")" -eq 2 ]
  grep -B12 'resilience.sleepwatcher_loaded' "$DOCTOR" | grep -q KEEP_AWAKE_TOOLS
  grep -B2 'resilience.amphetamine_installed' "$DOCTOR" | grep -q KEEP_AWAKE_TOOLS
}

# Run only the sleepwatcher LaunchAgent block of the wizard, with stubs, so
# the test never installs anything or opens the App Store.
_setup_sleepwatcher_block() {
  local block
  block="$(sed -n '/^# keep_awake_tools: same default as bin\/dotfiles-doctor/,/^fi$/p' "$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup")"
  ( DOTFILES_KEEP_AWAKE_TOOLS="$1"
    ok() { echo "ok: $*"; }; warn() { echo "warn: $*"; }; hint() { echo "hint: $*"; }
    launchctl() { echo "PID Status Label"; }
    eval "$block" )
}

@test "resilience setup does not warn about sleepwatcher when keep_awake_tools is off" {
  run _setup_sleepwatcher_block false
  [[ "$output" != *"not loaded"* ]]
  [[ "$output" == *"keep_awake_tools is false"* ]]
  run _setup_sleepwatcher_block true
  [[ "$output" == *"warn: sleepwatcher LaunchAgent not loaded"* ]]
}

@test "keep_awake_tools=true loads agent-keepawake on a core Mac with Claude Code" {
  PROFILE=core KEEP_AWAKE_TOOLS=true HOME="$BATS_TEST_TMPDIR"
  mkdir -p "$HOME/.local/bin" && printf '#!/bin/sh\n' > "$HOME/.local/bin/claude" && chmod +x "$HOME/.local/bin/claude"
  run should_skip_agent agent-keepawake
  [ "$status" -eq 1 ]
}

@test "keep_awake_tools=false skips agent-keepawake, even on full" {
  PROFILE=full KEEP_AWAKE_TOOLS=false
  run should_skip_agent agent-keepawake
  [ "$status" -eq 0 ]
}

@test "doctor expects agent-keepawake only when keep_awake_tools is on" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh"
  grep 'resilience.agent_keepawake_loaded' -A1 "$DOCTOR" | grep -q 'KEEP_AWAKE_TOOLS:-true'
  grep 'resilience.agent_keepawake_battery_policy' -A1 "$DOCTOR" | grep -q 'KEEP_AWAKE_TOOLS:-true'
  ! grep -q 'DOTFILES_PROFILE:-full}\\" != full' "$DOCTOR"
}

@test "lid-close report does not claim coverage when agent-keepawake is not loaded" {
  SETUP="$BATS_TEST_DIRNAME/../bin/dotfiles-resilience-setup"
  grep -q 'launchctl print "gui/$(id -u)/com.dotfiles.agent-keepawake"' "$SETUP"
  grep -q 'are NOT covered: the agent-keepawake LaunchAgent is not loaded' "$SETUP"
}

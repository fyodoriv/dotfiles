#!/usr/bin/env bats
# Drift detector for the sources that set Claude Code's default model.
#
# Per AGENTS.md § Model Configuration, two sources write the same keys in
# ~/.claude/settings.json and must agree:
#
# Source 1: Agentfile.yaml defaultModel/defaultEffort (agentbrew model sync)
# Source 2: DESIRED_MODEL/DESIRED_EFFORT in
#           .chezmoiscripts/run_after_claude-settings-model.sh (chezmoi apply
#           and the claude.model_default doctor fix)
#
# If they differ, each sync flips the model back and forth.

load test_helper

EXPECTED_MODEL="claude-opus-5-5"
EXPECTED_EFFORT="medium"

@test "claude model: Agentfile.yaml sets defaultModel=$EXPECTED_MODEL and defaultEffort=$EXPECTED_EFFORT" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  grep -qE "^defaultModel:[[:space:]]*$EXPECTED_MODEL[[:space:]]*$" "$agentfile"
  grep -qE "^defaultEffort:[[:space:]]*$EXPECTED_EFFORT[[:space:]]*$" "$agentfile"
}

@test "claude model: Agentfile.yaml does not skip claude-code in modelOverrides" {
  local agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"
  ! grep -qE '^[[:space:]]+claude-code:[[:space:]]*null' "$agentfile"
}

@test "claude model: settings pin script writes $EXPECTED_MODEL at $EXPECTED_EFFORT effort" {
  local script="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_claude-settings-model.sh"
  grep -qE "^DESIRED_MODEL=\"$EXPECTED_MODEL\"$" "$script"
  grep -qE "^DESIRED_EFFORT=\"$EXPECTED_EFFORT\"$" "$script"
}

@test "claude model: doctor expects $EXPECTED_MODEL at $EXPECTED_EFFORT effort" {
  local doctor="$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  grep -qF "[ \"\$m\" = \"$EXPECTED_MODEL\" ] && [ \"\$e\" = \"$EXPECTED_EFFORT\" ]" "$doctor"
}

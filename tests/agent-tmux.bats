#!/usr/bin/env bats
# Tests for bin/agent-tmux

load test_helper

@test "agent-tmux: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/agent-tmux" ]
}

@test "agent-tmux: --help prints usage" {
  run bash "$BATS_TEST_DIRNAME/../bin/agent-tmux" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-tmux"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"tmux"* ]]
}

@test "agent-tmux: --ls lists sessions without error" {
  run bash "$BATS_TEST_DIRNAME/../bin/agent-tmux" --ls
  # May return 0 (sessions listed) or 1 (no sessions) — both are valid
  [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

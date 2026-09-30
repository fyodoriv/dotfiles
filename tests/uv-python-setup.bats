#!/usr/bin/env bats
# Tests for .chezmoiscripts/run_after_uv-python-setup.sh

load test_helper

@test "uv-python-setup: script exists" {
  [ -f "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_uv-python-setup.sh" ]
}

@test "uv-python-setup: script is valid bash" {
  run bash -n "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_uv-python-setup.sh"
  [ "$status" -eq 0 ]
}

@test "uv-python-setup: references uv python install" {
  grep -q "uv python" "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_uv-python-setup.sh"
}

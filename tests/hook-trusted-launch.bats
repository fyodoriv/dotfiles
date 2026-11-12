#!/usr/bin/env bats

@test "trusted hook launcher rejects unsafe inputs and binds a synthetic child" {
  run python3 tests/hook_trusted_launch_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 14 tests"*"OK"* ]]
}

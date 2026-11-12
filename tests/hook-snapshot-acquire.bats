#!/usr/bin/env bats

@test "source acquisition refuses unsafe or changed inputs" {
  run python3 tests/hook_snapshot_acquire_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 10 tests"*"OK"* ]]
}

#!/usr/bin/env bats

@test "run directory locality rejects unknown or changed evidence" {
  run python3 tests/hook_run_locality_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

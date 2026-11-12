#!/usr/bin/env bats

@test "status timing binds the effective endpoint helper" {
  run python3 tests/hook_effective_helper_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 3 tests"*"OK"* ]]
}

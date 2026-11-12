#!/usr/bin/env bats

@test "private timing records reject unsafe files without blocking" {
  run python3 tests/hook_pair_private_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 4 tests"*"OK"* ]]
}

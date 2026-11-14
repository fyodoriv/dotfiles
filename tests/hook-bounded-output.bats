#!/usr/bin/env bats

@test "hook output retention is bounded and private" {
  run python3 tests/hook_bounded_output_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

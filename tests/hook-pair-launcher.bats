#!/usr/bin/env bats

@test "timing launcher preparation fails closed on invalid evidence" {
  run python3 tests/hook_pair_launcher_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 5 tests"*"OK"* ]]
}

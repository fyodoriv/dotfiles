#!/usr/bin/env bats

@test "pinned Cargo fixture targets reject altered evidence" {
  run python3 tests/test_cargo_targets.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 1 test"*"OK"* ]]
}

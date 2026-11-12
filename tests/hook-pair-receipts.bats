#!/usr/bin/env bats

@test "private timing records reject incomplete or altered evidence" {
  run python3 tests/hook_pair_receipts_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 4 tests"*"OK"* ]]
}

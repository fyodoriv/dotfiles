#!/usr/bin/env bats

@test "status pair summary rejects incomplete or invalid observations" {
  run python3 tests/hook_status_pairs_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 16 tests"*"OK"* ]]
}

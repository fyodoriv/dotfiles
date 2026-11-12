#!/usr/bin/env bats

@test "pinned source roles reject altered declarations" {
  run python3 tests/test_reference_roles.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 1 test"*"OK"* ]]
}

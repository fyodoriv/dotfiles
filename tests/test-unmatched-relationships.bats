#!/usr/bin/env bats

@test "pinned relative test relationships reject altered evidence" {
  run python3 tests/test_unmatched_relationships.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

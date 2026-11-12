#!/usr/bin/env bats

@test "pinned test source references reject altered evidence" {
  run python3 tests/test_source_references.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 1 test"*"OK"* ]]
}

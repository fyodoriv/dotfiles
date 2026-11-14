#!/usr/bin/env bats

@test "mapping request is private, exclusive and bound" {
  run python3 tests/hook_mapping_intent_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 3 tests"*"OK"* ]]
}

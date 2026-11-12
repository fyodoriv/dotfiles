#!/usr/bin/env bats

@test "mapping collection requires an unchanged pre-fetch request" {
  run python3 tests/hook_mapping_controller_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 1 test"*"OK"* ]]
}

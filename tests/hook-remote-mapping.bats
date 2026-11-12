#!/usr/bin/env bats

@test "remote source mapping rejects unverified commit and tree records" {
  run python3 tests/hook_remote_mapping_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 10 tests"*"OK"* ]]
}

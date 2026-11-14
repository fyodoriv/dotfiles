#!/usr/bin/env bats

@test "private source snapshots reject changed or unsafe inputs" {
  run python3 tests/hook_source_snapshot_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 6 tests"*"OK"* ]]
}

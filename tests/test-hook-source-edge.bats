#!/usr/bin/env bats

@test "pinned hook source edge rejects altered anchors and identities" {
  run python3 tests/test_hook_source_edge.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

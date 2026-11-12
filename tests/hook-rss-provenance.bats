#!/usr/bin/env bats

@test "hook memory receipt rejects invalid provenance without running timings" {
  run python3 tests/hook_rss_provenance_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 20 tests"*"OK"* ]]
}

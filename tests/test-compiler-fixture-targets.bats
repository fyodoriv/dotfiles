#!/usr/bin/env bats

@test "compiler fixture targets reject altered declarations and identities" {
  run python3 tests/test_compiler_fixture_targets.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

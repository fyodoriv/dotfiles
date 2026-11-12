#!/usr/bin/env bats

@test "timing binding rejects altered identities and observations" {
  run python3 tests/hook_pair_binding_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 7 tests"*"OK"* ]]
}

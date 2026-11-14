#!/usr/bin/env bats

@test "source audit rejects ambiguous or mismatched root metadata" {
  run python3 tests/hook_source_audit_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

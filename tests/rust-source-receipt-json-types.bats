#!/usr/bin/env bats
# Reads docs/plans/strict_receipt_json.py through the seven checkers.

@test "source receipt checkers reject JSON type confusion and duplicate keys" {
  run python3 tests/source_receipt_json_types_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 4 tests"*"OK"* ]]
}

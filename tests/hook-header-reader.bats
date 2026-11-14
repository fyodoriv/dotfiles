#!/usr/bin/env bats

@test "synthetic hook header reader rejects unsafe inputs" {
  run python3 "$BATS_TEST_DIRNAME/hook_header_reader_test.py"
  [ "$status" -eq 0 ]
}

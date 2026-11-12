#!/usr/bin/env bats

@test "bounded hook shebang decoder rejects ambiguous headers" {
  run python3 "$BATS_TEST_DIRNAME/hook_shebang_test.py"
  [ "$status" -eq 0 ]
}

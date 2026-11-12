#!/usr/bin/env bats

@test "timing worker refuses invalid private intent and admission" {
  run python3 tests/hook_pair_worker_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 7 tests"*"OK"* ]]
}

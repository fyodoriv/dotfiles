#!/usr/bin/env bats

@test "host-load source declarations match pinned sources" {
  run python3 "$BATS_TEST_DIRNAME/host-load-relationships-test.py"
  [ "$status" -eq 0 ]
  run python3 "$BATS_TEST_DIRNAME/../docs/plans/host-load-relationships.py" --check
  [ "$status" -eq 0 ]
}

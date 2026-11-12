#!/usr/bin/env bats

@test "conditional doctor fixture relationships match pinned sources" {
  run python3 "$BATS_TEST_DIRNAME/doctor-fixture-relationships-test.py"
  [ "$status" -eq 0 ]
  run python3 "$BATS_TEST_DIRNAME/../docs/plans/doctor-fixture-relationships.py" --check
  [ "$status" -eq 0 ]
}

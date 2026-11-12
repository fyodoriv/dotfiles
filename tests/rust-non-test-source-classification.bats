#!/usr/bin/env bats

@test "non-test source classification rejects planted receipt errors" {
  run python3 docs/plans/non-test-source-classification.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 34 sources; rejected 272 planted errors" ]
}

@test "non-test classification regenerates from pinned sources" {
  run bash -c 'python3 docs/plans/non-test-source-classification.py --generate | cmp - docs/plans/non-test-source-classification.json'
  [ "$status" -eq 0 ]
}

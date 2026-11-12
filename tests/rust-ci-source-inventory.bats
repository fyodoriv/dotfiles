#!/usr/bin/env bats

@test "CI source receipt rejects planted omissions and wrong anchors" {
  run python3 docs/plans/ci-source-inventory.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 5 scripts and 7 references; rejected 67 planted errors" ]
}

@test "CI source receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/ci-source-inventory.py --generate | cmp - docs/plans/ci-source-inventory.json'
  [ "$status" -eq 0 ]
}

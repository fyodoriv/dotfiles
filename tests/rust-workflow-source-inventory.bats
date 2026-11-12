#!/usr/bin/env bats

@test "workflow source receipt rejects planted omissions and wrong anchors" {
  run python3 docs/plans/workflow-source-inventory.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 5 workflows and 29 run candidates; rejected 165 planted errors" ]
}

@test "workflow source receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/workflow-source-inventory.py --generate | cmp - docs/plans/workflow-source-inventory.json'
  [ "$status" -eq 0 ]
}

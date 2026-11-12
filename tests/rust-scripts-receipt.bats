#!/usr/bin/env bats

@test "scripts receipt rejects planted identity and anchor errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --scripts
  [ "$status" -eq 0 ]
  [ "$output" = "checked 8/8 files and 18 anchors; rejected 112 planted errors" ]
}

@test "scripts receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-scripts | cmp - docs/plans/rust-scripts-source-receipt.json'
  [ "$status" -eq 0 ]
}

@test "receipt usage lists both scripts modes" {
  run python3 docs/plans/doctor-source-receipt-check.py --invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"--scripts"*"--generate-scripts"* ]]
}

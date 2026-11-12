#!/usr/bin/env bats

@test "current bin receipt rejects planted identity and anchor errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --bin-sources
  [ "$status" -eq 0 ]
  [ "$output" = "checked 135/135 files and 135 anchors; rejected 1215 planted errors" ]
}

@test "current bin receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-bin-sources | cmp - docs/plans/rust-current-bin-source-receipt.json'
  [ "$status" -eq 0 ]
}

@test "receipt usage lists both current bin modes" {
  run python3 docs/plans/doctor-source-receipt-check.py --invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"--bin-sources"*"--generate-bin-sources"* ]]
}

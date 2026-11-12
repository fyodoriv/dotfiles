#!/usr/bin/env bats

@test "root source receipt rejects planted identity and anchor errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --root-sources
  [ "$status" -eq 0 ]
  [ "$output" = "checked 6/6 files and 22 anchors; rejected 118 planted errors" ]
}

@test "root source receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-root-sources | cmp - docs/plans/rust-root-source-receipt.json'
  [ "$status" -eq 0 ]
}

@test "receipt usage lists both root source modes" {
  run python3 docs/plans/doctor-source-receipt-check.py --invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"--root-sources"*"--generate-root-sources"* ]]
}

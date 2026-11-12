#!/usr/bin/env bats

@test "pinned library receipt rejects planted identity and anchor errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --libraries
  [ "$status" -eq 0 ]
  [ "$output" = "checked 63/63 files and 63 anchors; rejected 505 planted errors" ]
}

@test "doctor receipt check keeps its existing behavior" {
  run python3 docs/plans/doctor-source-receipt-check.py
  [ "$status" -eq 0 ]
  [ "$output" = "checked 33/33 files and 33 anchors; rejected 264 planted errors" ]
}

@test "library receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-libraries | cmp - docs/plans/rust-library-source-receipt.json'
  [ "$status" -eq 0 ]
}

@test "library source-syntax receipt rejects planted row errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --library-callers
  [ "$status" -eq 0 ]
  [ "$output" = "checked 277 source-syntax rows; rejected 1662 planted errors" ]
}

@test "library source-syntax receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-library-callers | cmp - docs/plans/rust-library-caller-receipt.json'
  [ "$status" -eq 0 ]
}

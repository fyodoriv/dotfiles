#!/usr/bin/env bats

@test "Git hook receipt rejects planted identity and anchor errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --git-hooks
  [ "$status" -eq 0 ]
  [ "$output" = "checked 3/3 files and 19 anchors; rejected 91 planted errors" ]
}

@test "Git hook receipt regenerates from the pinned tree" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-git-hooks | cmp - docs/plans/rust-git-hook-source-receipt.json'
  [ "$status" -eq 0 ]
}

@test "receipt usage lists both Git hook modes" {
  run python3 docs/plans/doctor-source-receipt-check.py --invalid
  [ "$status" -ne 0 ]
  [[ "$output" == *"--git-hooks"*"--generate-git-hooks"* ]]
}

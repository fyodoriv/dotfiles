#!/usr/bin/env bats

@test "current doctor anchors reject planted identity errors" {
  run python3 docs/plans/doctor-source-receipt-check.py --current-doctor
  [ "$status" -eq 0 ]
  [ "$output" = "checked 33/33 files and 33 anchors; rejected 264 planted errors" ]
}

@test "current doctor anchors regenerate from pinned sources" {
  run bash -c 'python3 docs/plans/doctor-source-receipt-check.py --generate-current-doctor | cmp - docs/plans/current-doctor-anchors.json'
  [ "$status" -eq 0 ]
}

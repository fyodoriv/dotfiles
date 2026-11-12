#!/usr/bin/env bats

@test "Bats discovery receipt rejects planted errors" {
  run python3 docs/plans/bats-discovery-receipt.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 383 candidates; rejected 2298 planted errors" ]
}

@test "Bats discovery receipt regenerates from pinned sources" {
  run bash -c 'python3 docs/plans/bats-discovery-receipt.py --generate | cmp - docs/plans/bats-discovery-receipt.json'
  [ "$status" -eq 0 ]
}

#!/usr/bin/env bats

@test "current bin boundaries reject planted anchor errors" {
  run python3 docs/plans/current-bin-boundaries.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 7 boundaries and 8 calls; rejected 56 planted errors" ]
}

@test "current bin boundaries regenerate from pinned sources" {
  run bash -c 'python3 docs/plans/current-bin-boundaries.py --generate | cmp - docs/plans/current-bin-boundaries.json'
  [ "$status" -eq 0 ]
}

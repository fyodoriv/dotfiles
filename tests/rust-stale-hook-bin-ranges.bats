#!/usr/bin/env bats

@test "stale hook and bin ranges reject planted receipt errors" {
  run python3 docs/plans/stale-hook-bin-ranges.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 3 sources, 13 ranges and 20 anchors; rejected 248 planted errors" ]
}

@test "stale hook and bin ranges regenerate from pinned sources" {
  run bash -c 'python3 docs/plans/stale-hook-bin-ranges.py --generate | cmp - docs/plans/stale-hook-bin-ranges.json'
  [ "$status" -eq 0 ]
}

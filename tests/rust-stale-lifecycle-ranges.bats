#!/usr/bin/env bats

@test "stale lifecycle ranges reject planted source errors" {
  run python3 docs/plans/stale-lifecycle-ranges.py --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^checked\ 3\ sources\ and\ ([1-9][0-9]*)\ ranges\;\ rejected\ ([1-9][0-9]*)\ planted\ errors$ ]]
  [ "${BASH_REMATCH[2]}" -eq "$((15 + 5 * BASH_REMATCH[1]))" ]
}

@test "stale lifecycle ranges regenerate from pinned sources" {
  run bash -c 'python3 docs/plans/stale-lifecycle-ranges.py --generate | cmp - docs/plans/stale-lifecycle-ranges.json'
  [ "$status" -eq 0 ]
}

@test "stale lifecycle receipt rejects ambiguous JSON types and keys" {
  run python3 tests/stale_lifecycle_ranges_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 2 tests"*"OK"* ]]
}

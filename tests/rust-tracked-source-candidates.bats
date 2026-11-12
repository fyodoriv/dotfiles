#!/usr/bin/env bats

@test "tracked source candidates reject every planted identity error" {
  run python3 docs/plans/tracked-source-candidates.py --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^checked\ ([1-9][0-9]*)\ candidates\;\ rejected\ ([1-9][0-9]*)\ planted\ errors$ ]]
  [ "${BASH_REMATCH[2]}" -eq "$((3 * BASH_REMATCH[1]))" ]
}

@test "tracked source candidates regenerate from the pinned tree" {
  run bash -c 'python3 docs/plans/tracked-source-candidates.py --generate | cmp - docs/plans/tracked-source-candidates.json'
  [ "$status" -eq 0 ]
}

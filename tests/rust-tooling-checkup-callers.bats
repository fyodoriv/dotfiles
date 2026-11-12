#!/usr/bin/env bats

@test "tooling-checkup references reject planted source errors" {
  run python3 docs/plans/tooling-checkup-callers.py --check
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^checked\ 11\ scripts\ and\ ([1-9][0-9]*)\ references\;\ rejected\ ([1-9][0-9]*)\ planted\ errors$ ]]
  [ "${BASH_REMATCH[2]}" -eq "$((44 + 5 * BASH_REMATCH[1]))" ]
}

@test "tooling-checkup references regenerate from pinned sources" {
  run bash -c 'python3 docs/plans/tooling-checkup-callers.py --generate | cmp - docs/plans/tooling-checkup-callers.json'
  [ "$status" -eq 0 ]
}

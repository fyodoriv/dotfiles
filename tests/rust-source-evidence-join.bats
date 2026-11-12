#!/usr/bin/env bats

@test "source evidence join handles overlaps, staleness and ambiguity" {
  run python3 tests/source_evidence_join_test.py
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ran 8 tests"*"OK"* ]]
}

@test "source evidence join rejects planted candidate errors" {
  run python3 docs/plans/source-evidence-join.py --check
  [ "$status" -eq 0 ]
  [ "$output" = "checked 744 candidates; rejected 5241 planted errors" ]
}

@test "source evidence join regenerates from pinned receipts" {
  run bash -c 'python3 docs/plans/source-evidence-join.py --generate | cmp - docs/plans/source-evidence-join.json'
  [ "$status" -eq 0 ]
}

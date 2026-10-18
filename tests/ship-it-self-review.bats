#!/usr/bin/env bats

load test_helper

REF="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
CMD="$BATS_TEST_DIRNAME/../commands/ship-it.md"

@test "ship-it reference has a self-review step before merge, with a skip rule" {
  grep -q '^## 6a\. Self-review before merge' "$REF"
  grep -q '/code-review' "$REF"
  grep -q '/code-review medium <PR number>' "$REF"
  grep -q 'its findings carry no' "$REF"
  grep -q 'Skip rule: skip the review for a diff that touches only docs' "$REF"
  grep -q '## Review' "$REF"
  # The step sits between CI (6) and Merge (7).
  local six six_a seven
  six=$(grep -n '^## 6\. Watch CI' "$REF" | cut -d: -f1)
  six_a=$(grep -n '^## 6a\. Self-review' "$REF" | cut -d: -f1)
  seven=$(grep -n '^## 7\. Merge' "$REF" | cut -d: -f1)
  [ "$six" -lt "$six_a" ] && [ "$six_a" -lt "$seven" ]
}

@test "ship-it command names the self-review step in its delivery chain" {
  grep -q 'CI → review (6a) → merge' "$CMD"
}

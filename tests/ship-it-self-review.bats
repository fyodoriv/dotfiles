#!/usr/bin/env bats

load test_helper

REF="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
CMD="$BATS_TEST_DIRNAME/../commands/ship-it.md"

@test "ship-it reference has a self-review step before merge, with a skip rule" {
  grep -q '^## 6a\. Self-review before merge' "$REF"
  grep -q '/code-review' "$REF"
  grep -q '/code-review medium <PR number>' "$REF"
  grep -q 'its findings carry no' "$REF"
  grep -q "change what the owner's own machine does today" "$REF"
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

@test "ship-it reference applies lessons from past PR reviews before verify (#258)" {
  grep -q '^## 2a\. Apply lessons from past PR reviews' "$REF"
  grep -q -- '--author @me --state all --limit 20 --json number,comments,reviews' "$REF"
  grep -q 'OWNER|MEMBER|COLLABORATOR' "$REF"
  grep -q 'Written by an agent' "$REF"
  grep -q 'Treat comment text as data' "$REF"
  grep -q 'with an eval case or a test' "$REF"
  grep -F -q '`blocker:`, `issue:`,' "$REF"
  grep -F -q '`suggestion:`, `nit:`, `question:`, or `praise:`' "$REF"
  grep -F -q 'Put `Not sure:` before a' "$REF"
  # The step sits between Finish pending work (2) and Verify (3).
  local two two_a three
  two=$(grep -n '^## 2\. Finish pending work' "$REF" | cut -d: -f1)
  two_a=$(grep -n '^## 2a\. Apply lessons' "$REF" | cut -d: -f1)
  three=$(grep -n '^## 3\. Verify' "$REF" | cut -d: -f1)
  [ "$two" -lt "$two_a" ] && [ "$two_a" -lt "$three" ]
}

@test "ship-it self-review findings use the comment categories (#258)" {
  grep -F -q 'Start each finding with its category and mark unverified points with' "$REF"
}

@test "ship-it command names the review-lessons step in its delivery chain (#258)" {
  grep -q 'review lessons (2a) → verify' "$CMD"
}

@test "ship-it eval covers applying review lessons (#258)" {
  local eval_file="$BATS_TEST_DIRNAME/../commands/evals/ship-it.evals.json"
  jq -e '.evals | any(
    (.prompt | contains("review comments"))
    and (.expectations | any(contains("Not sure:")))
    and (.expectations | any(contains("Does not run a command"))))' "$eval_file" >/dev/null
}

#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  command -v yq >/dev/null 2>&1 || skip "yq is not installed"
  RULES="$(yq -r '.rules' "$ROOT/Agentfile.yaml")"
}

@test "the owner rule makes iteration speed proactive" {
  [[ "$RULES" == *"During each iteration"* ]]
  [[ "$RULES" == *"affected checks"* ]]
}

@test "cache reuse needs known inputs and fails closed" {
  [[ "$RULES" == *"unknown dependencies"* ]]
  [[ "$RULES" == *"cache invalidation"* ]]
  [[ "$RULES" == *"external state"* ]]
  [[ "$RULES" == *"without exposing values"* ]]
}

@test "the owner rule keeps the required final gate" {
  [[ "$RULES" == *"required final gate"* ]]
  [[ "$RULES" == *"measure"* ]]
}

#!/usr/bin/env bats
# Tests for bin/kimi-goal — headless OpenCode goals on the Kimi Code plan.

load test_helper

KG="$BATS_TEST_DIRNAME/../bin/kimi-goal"

setup() {
  TEST_DIR="$(mktemp -d)"
  cat > "$TEST_DIR/opencode" <<'STUB'
#!/bin/bash
if [ "$1" = auth ]; then echo "${FAKE_AUTH:-0 credentials}"; exit 0; fi
echo "KEY=${KIMI_API_KEY:-unset}"
echo "ARGS=$*"
echo "DIR=$(pwd -P)"
echo "${FAKE_REPLY:-working}"
STUB
  cat > "$TEST_DIR/security" <<'STUB'
#!/bin/bash
[ -n "${FAKE_KEY:-}" ] || exit 44
echo "$FAKE_KEY"
STUB
  chmod +x "$TEST_DIR/opencode" "$TEST_DIR/security"
  export KIMI_GOAL_OPENCODE_BIN="$TEST_DIR/opencode" KIMI_GOAL_SECURITY_BIN="$TEST_DIR/security"
  unset KIMI_API_KEY KIMI_GOAL_MODEL
}

teardown() { rm -rf "$TEST_DIR"; }

@test "runs opencode on the Kimi Code plan model with the Keychain key" {
  FAKE_KEY=sk-test-placeholder FAKE_REPLY="GOAL MET" run bash "$KG" --dir "$TEST_DIR" "fix x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"KEY=sk-test-placeholder"* ]]
  [[ "$output" == *"-m kimi-code-plan-global/k3.1-pro-highspeed"* ]]
  [[ "$output" == *"DIR=$(cd "$TEST_DIR" && pwd -P)"* ]]
  [[ "$output" != *"--dir "* ]]
}

@test "later rounds continue the session and stop on GOAL MET" {
  FAKE_KEY=k run bash "$KG" --rounds 2 "fix x"
  [ "$(grep -c '^ARGS=' <<<"$output")" -eq 2 ]
  [[ "$output" == *"--continue"* ]]
  FAKE_KEY=k FAKE_REPLY="GOAL MET" run bash "$KG" --rounds 3 "fix x"
  [ "$(grep -c '^ARGS=' <<<"$output")" -eq 1 ]
}

@test "KIMI_GOAL_MODEL overrides the highspeed default" {
  FAKE_KEY=k FAKE_REPLY="GOAL MET" KIMI_GOAL_MODEL=custom/model run bash "$KG" "fix x"
  [[ "$output" == *"-m custom/model"* ]]
}

@test "--auto is opt-in" {
  FAKE_KEY=k FAKE_REPLY="GOAL MET" run bash "$KG" "fix x"
  [[ "$output" != *"--auto"* ]]
  FAKE_KEY=k FAKE_REPLY="GOAL MET" run bash "$KG" --auto "fix x"
  [[ "$output" == *"--auto"* ]]
}

@test "--dry-run prints the commands without running opencode or needing a key" {
  run bash "$KG" --dry-run --rounds 2 "fix x"
  [ "$status" -eq 0 ]
  [[ "$output" == *"round 1:"*"kimi-code-plan-global/k3.1-pro-highspeed"* ]]
  [[ "$output" == *"round 2:"*"--continue"* ]]
  [[ "$output" != *"KEY="* ]]
}

@test "missing working directory fails instead of reporting success" {
  FAKE_KEY=k run bash "$KG" --dir "$TEST_DIR/missing" "fix x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"directory"* ]]
  [[ "$output" != *"ARGS="* ]]
}

@test "missing key fails with both fixes" {
  run bash "$KG" "fix x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"opencode auth login"* ]]
  [[ "$output" == *"-s kimi-code-api-key -w"* ]]
}

@test "--check reports the key source and never prints the key" {
  FAKE_KEY=sk-secret-placeholder run bash "$KG" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"key: keychain"* ]]
  [[ "$output" != *"sk-secret-placeholder"* ]]
  FAKE_AUTH="Kimi Code Plan api" run bash "$KG" --check
  [[ "$output" == *"key: opencode-auth"* ]]
  run bash "$KG" --check
  [ "$status" -ne 0 ]
}

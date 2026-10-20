#!/usr/bin/env bats
# private_dot_agent-browser/modify_config.json sets "cdp": "9223" and keeps
# other keys, so agent-browser attaches to the one agents Chrome by default.

SCRIPT="$BATS_TEST_DIRNAME/../private_dot_agent-browser/modify_config.json"

@test "empty config gets cdp 9223" {
  run bash "$SCRIPT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .cdp)" = "9223" ]
}

@test "existing keys are kept and cdp is set" {
  run bash "$SCRIPT" <<<'{"headed":false,"cdp":"9222"}'
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .cdp)" = "9223" ]
  [ "$(printf '%s' "$output" | jq -r .headed)" = "false" ]
}

@test "invalid JSON is passed through unchanged" {
  run bash "$SCRIPT" <<<'not json'
  [ "$status" -eq 0 ]
  [ "$output" = "not json" ]
}

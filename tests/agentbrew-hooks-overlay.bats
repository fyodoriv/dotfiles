#!/usr/bin/env bats
# Tests for dot_config/agentbrew/hooks-overlay/modify_manifest.yaml

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../dot_config/agentbrew/hooks-overlay/modify_manifest.yaml"
HOOK="gh-pr-body-requires-docs"

render() {
  printf '%s' "$1" | sh "$SCRIPT"
}

@test "hooks overlay: empty input creates version and enabled list" {
  run render ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"version: 1"* ]]
  [[ "$output" == *"enabled:"* ]]
  [[ "$output" == *"  - $HOOK"* ]]
}

@test "hooks overlay: keeps comments and the disabled list, appends enabled" {
  input=$'version: 1\n\n# Verifier hooks hang on this machine.\ndisabled:\n  - codify-repeated-work\n  - rule-skill-location\n'
  run render "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == "$input"* ]]
  [[ "$output" == *$'enabled:\n  - '"$HOOK"* ]]
  [ "$(grep -c "$HOOK" <<<"$output")" -eq 1 ]
}

@test "hooks overlay: already enabled is a byte-for-byte no-op" {
  input=$'version: 1\ndisabled:\n  - a\n\n# Opt-in Bash hooks.\nenabled:\n  - '"$HOOK"$'\n'
  run render "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "${input%$'\n'}" ]
}

@test "hooks overlay: adds the hook to an enabled list that has other IDs" {
  input=$'version: 1\nenabled:\n    - other-hook\n    - second-hook\ndisabled:\n  - x\n'
  run render "$input"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'enabled:\n    - '"$HOOK"$'\n    - other-hook\n    - second-hook\ndisabled:\n  - x'* ]]
}

@test "hooks overlay: replaces an empty inline enabled list" {
  run render $'version: 1\nenabled: []\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'enabled:\n  - '"$HOOK"* ]]
  [[ "$output" != *"[]"* ]]
}

@test "hooks overlay: a machine that disabled the hook keeps it disabled" {
  input=$'version: 1\ndisabled:\n  - '"$HOOK"$'\n'
  run render "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "${input%$'\n'}" ]
}

@test "hooks overlay: output is stable when applied twice" {
  once="$(render $'version: 1\ndisabled:\n  - a\n')"
  twice="$(render "$once")"
  [ "$once" = "$twice" ]
}

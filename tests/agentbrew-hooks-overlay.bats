#!/usr/bin/env bats
# Tests for dot_config/agentbrew/hooks-overlay/modify_manifest.yaml.tmpl

load test_helper

TEMPLATE="$BATS_TEST_DIRNAME/../dot_config/agentbrew/hooks-overlay/modify_manifest.yaml.tmpl"
HOOK="gh-pr-body-requires-docs"

setup() {
  SCRIPT="$(mktemp)"
  chezmoi execute-template --source "$BATS_TEST_DIRNAME/.." --override-data '{"owner_machine":true}' \
    < "$TEMPLATE" > "$SCRIPT"
}

teardown() { rm -f "$SCRIPT"; }

render() {
  printf '%s' "$1" | DOTFILES_OVERLAY_HOOKS="$HOOK" sh "$SCRIPT"
}

render_all() {
  printf '%s' "$1" | env -u DOTFILES_OVERLAY_HOOKS sh "$SCRIPT"
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

@test "hooks overlay: owner-only hooks stay off on a new user's Mac" {
  chezmoi execute-template --source "$BATS_TEST_DIRNAME/.." --override-data '{"owner_machine":false}' \
    < "$TEMPLATE" > "$SCRIPT"
  input=$'version: 1\ndisabled:\n  - x\n'
  run render_all "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "${input%$'\n'}" ]
}

@test "hooks overlay: the owner's Mac turns the owner-only hooks on" {
  run render_all ""
  [ "$status" -eq 0 ]
  for hook in perf-task-review poll-loop-hint usage-tip no-home-crawl async-human-comms-blocks gdoc-surgical-edit-only; do
    [[ "$output" == *"  - $hook"* ]]
  done
}

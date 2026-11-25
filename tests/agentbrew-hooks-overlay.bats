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

@test "hooks overlay: adds one entry to a nonempty inline enabled list" {
  input=$'version: 1\nenabled: [keep-first, "keep-second"  ] # keep this note\ndisabled:\n  - keep-disabled\n'
  expected=$'version: 1\nenabled: [keep-first, "keep-second", '"$HOOK"$'  ] # keep this note\ndisabled:\n  - keep-disabled'
  run render "$input"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^enabled:' <<<"$output")" -eq 1 ]
  [ "$output" = "$expected" ]

  run render "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "hooks overlay: keeps quoted inline hook IDs already enabled" {
  for quote in "'" '"'; do
    input="version: 1"$'\nenabled: ['"$quote$HOOK$quote"$', keep-hook] # machine note'
    run render "$input"
    [ "$status" -eq 0 ]
    [ "$output" = "$input" ]
  done
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
  for hook in perf-task-review poll-loop-hint no-home-crawl gdoc-surgical-edit-only; do
    [[ "$output" == *"  - $hook"* ]]
  done
}

@test "hooks overlay: all seven owner workflow guards are registered" {
  run render_all ""
  [ "$status" -eq 0 ]
  local hook missing=()
  for hook in no-commit-no-verify no-git-add-all gh-pr-agent-artifacts-require-tests \
    gh-pr-skill-requires-evals no-binary-screenshots gh-pr-body-no-review-response \
    gh-pr-body-related-prs-not-first; do
    if ! grep -Fxq "  - $hook" <<<"$output"; then
      missing+=("$hook")
    fi
  done
  if [ "${#missing[@]}" -ne 0 ]; then
    printf 'Missing owner hook: %s\n' "${missing[@]}" >&2
    return 1
  fi
}

@test "pre-commit header does not recommend bypassing validation" {
  local header
  header="$(awk '/^set -o/{exit} {print}' "$BATS_TEST_DIRNAME/../git-hooks/pre-commit")"
  [[ "$header" != *'--no-verify'* ]]
}

render_retirement() {
  printf '%s' "$1" | DOTFILES_OVERLAY_HOOKS='' sh "$SCRIPT"
}

@test "retired communication hook is absent from fresh owner defaults" {
  run render_all ""
  [ "$status" -eq 0 ]
  [[ "$output" != *'  - async-human-comms-blocks'* ]]
  [[ "$output" == *'  - perf-task-review'* ]]
}

@test "retired communication hook migrates block lists and keeps disabled choices" {
  input=$'version: 1\nenabled:\n  - async-human-comms-blocks # old hook\n  - "async-human-comms-blocks"\n  - \'async-human-comms-blocks\'\n  - async-human-comms-blocks-custom\ndisabled:\n  - async-human-comms-blocks\n'
  expected=$'version: 1\nenabled:\n  # old hook\n  - async-human-comms-blocks-custom\ndisabled:\n  - async-human-comms-blocks'
  run render_retirement "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  run render_retirement "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "retired communication hook migrates inline lists" {
  run render_retirement $'version: 1\nenabled: [async-human-comms-blocks, "async-human-comms-blocks", keep-hook]\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled: [keep-hook]' ]
}

@test "retired IDs with mismatched inline quotes refuse without output" {
  for hook in usage-tip async-human-comms-blocks; do
    run render_retirement "version: 1
enabled: [\"$hook', keep-hook]"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
  done
}

@test "custom override cannot restore the retired communication hook" {
  run bash -c 'printf "%s" "$1" | DOTFILES_OVERLAY_HOOKS="async-human-comms-blocks keep-custom" sh "$2"' test '' "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *'  - async-human-comms-blocks'* ]]
  [[ "$output" == *'  - keep-custom'* ]]
}

@test "R01 retired usage-tip is absent from fresh owner defaults" {
  run render_all ""
  [ "$status" -eq 0 ]
  [[ "$output" != *'  - usage-tip'* ]]
  [[ "$output" == *'  - perf-task-review'* ]]
}

@test "R02 migrate an enabled entry and preserve all unrelated lines" {
  input=$'version: 1\n# machine note\nenabled:\n  - keep-first\n  - usage-tip\n  - keep-last\ndisabled:\n  - user-off\n'
  expected=$'version: 1\n# machine note\nenabled:\n  - keep-first\n  - keep-last\ndisabled:\n  - user-off'
  run render_retirement "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "R03 single-quoted retired ID migrates without touching similar names" {
  run render_retirement $'version: 1\nenabled:\n  - \'usage-tip\'\n  - usage-tip-custom\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled:\n  - usage-tip-custom' ]
}

@test "R03 double-quoted retired ID migrates without touching similar names" {
  run render_retirement $'version: 1\nenabled:\n  - "usage-tip"\n  - custom-usage-tip\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled:\n  - custom-usage-tip' ]
}

@test "R04 preserve comments on retired and unrelated entries" {
  input=$'version: 1\n# usage-tip is retired\nenabled:\n  - usage-tip # keep this note\n  - keep-hook # usage-tip is just text here\n'
  expected=$'version: 1\n# usage-tip is retired\nenabled:\n  # keep this note\n  - keep-hook # usage-tip is just text here'
  run render_retirement "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "R05 preserve all disabled choices byte-for-byte" {
  input=$'version: 1\ndisabled:\n  - usage-tip # owner opt-out\n  - keep-off\nenabled:\n  - keep-on\n'
  run render_retirement "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "${input%$'\n'}" ]
}

@test "R06 custom hook override cannot resurrect the retired ID" {
  run bash -c 'printf "%s" "$1" | DOTFILES_OVERLAY_HOOKS="usage-tip keep-custom" sh "$2"' test '' "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\n\n# Opt-in agentbrew hooks that dotfiles turns on for every machine.\nenabled:\n  - keep-custom' ]
}

@test "R07 exact ID migration does not touch other sections or substring IDs" {
  input=$'version: 1\nmetadata:\n  - usage-tip\n# usage-tip\nenabled:\n  - usage-tip-extra\n  - before-usage-tip\n'
  run render_retirement "$input"
  [ "$status" -eq 0 ]
  [ "$output" = "${input%$'\n'}" ]
}

@test "R08 retirement is stable on the second apply" {
  input=$'version: 1\nenabled:\n  - usage-tip\n  - keep-hook\n'
  once="$(render_retirement "$input")"
  [ "$once" = $'version: 1\nenabled:\n  - keep-hook' ]
  twice="$(render_retirement "$once")"
  [ "$twice" = "$once" ]
}

@test "R09 non-owner existing enabled entry is retired without owner defaults" {
  chezmoi execute-template --source "$BATS_TEST_DIRNAME/.." --override-data '{"owner_machine":false}' < "$TEMPLATE" > "$SCRIPT"
  run render_all $'version: 1\nenabled:\n  - usage-tip\n  - user-hook\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled:\n  - user-hook' ]
}

@test "R10 simple inline enabled list retires only the exact ID" {
  run render_retirement $'version: 1\nenabled: [usage-tip, keep-hook] # machine note\ndisabled: [keep-off]\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled: [keep-hook] # machine note\ndisabled: [keep-off]' ]
}

@test "R10 inline single retired ID becomes an empty enabled list" {
  run render_retirement $'version: 1\nenabled: ["usage-tip"]\n'
  [ "$status" -eq 0 ]
  [ "$output" = $'version: 1\nenabled: []' ]
}

@test "R10 ambiguous enabled anchor refuses without output" {
  run render_retirement $'version: 1\nenabled: &shared\n  - usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R11 spaced enabled key refuses without output" {
  run render_retirement $'version: 1\nenabled :\n  - usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R11 quoted enabled key refuses without output" {
  run render_retirement $'version: 1\n"enabled":\n  - usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R11 anchored enabled item refuses without output" {
  run render_retirement $'version: 1\nenabled:\n  - &tip usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R11 aliased enabled item refuses without output" {
  run render_retirement $'version: 1\ntip: &tip usage-tip\nenabled:\n  - *tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R11 indented root mapping refuses without output" {
  run render_retirement $'  version: 1\n  enabled:\n    - usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R12 indentless enabled sequence refuses without output" {
  run render_retirement $'version: 1\nenabled:\n- usage-tip\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R12 root flow mapping refuses without output" {
  run render_retirement $'{enabled: [usage-tip]}\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "R12 hash inside a distinct scalar refuses without deleting it" {
  run render_retirement $'version: 1\nenabled:\n  - usage-tip#custom\n  - keep-hook\n'
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

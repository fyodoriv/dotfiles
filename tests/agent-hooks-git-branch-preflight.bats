#!/usr/bin/env bats

setup() {
  HOOK="$BATS_TEST_DIRNAME/../agent-hooks/block-dangerous-git.sh"
  COMPARISON='test "$(git branch --show-current)" = "$(gh pr view 42 --json headRefName --jq .headRefName)"'
  export PREFLIGHT_EXECUTED="$BATS_TEST_TMPDIR/unexpected-execution"
  mkdir "$BATS_TEST_TMPDIR/bin"
  for name in git gh; do
    printf '%s\n' '#!/bin/bash' 'printf "unexpected\n" >> "$PREFLIGHT_EXECUTED"' 'exit 97' > "$BATS_TEST_TMPDIR/bin/$name"
    chmod +x "$BATS_TEST_TMPDIR/bin/$name"
  done
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

run_hook_input() {
  run bash -c 'jq -n --arg command "$1" --arg cwd "$2" "{cwd:\$cwd, tool_input:{command:\$command}}" | "$3"' \
    _ "$1" "$BATS_TEST_TMPDIR" "$HOOK"
  [ ! -e "$PREFLIGHT_EXECUTED" ]
}

@test "branch metadata preflight permits the original delivery shape" {
  tail=' && test "$(git rev-parse --short=8 HEAD)" = abcdef01 && test -z "$(git status --short)" && git merge --no-edit origin/main && git diff --check origin/main...HEAD && git push'
  run_hook_input "$COMPARISON$tail"
  [ "$status" -eq 0 ]
}

@test "branch metadata preflight permits the isolated comparison" {
  run_hook_input "$COMPARISON"
  [ "$status" -eq 0 ]
}

@test "branch metadata preflight preserves the existing standalone lookup" {
  run_hook_input 'git branch --show-current'
  [ "$status" -eq 0 ]
}

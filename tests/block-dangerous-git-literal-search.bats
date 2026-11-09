#!/usr/bin/env bats
# Frozen controls from docs/plans/git-guard-literal-search-472.md.

probe() {
  jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | ./agent-hooks/block-dangerous-git.sh
}

@test "safe 1: rg literal branch delete pattern passes" {
  run probe "rg 'git branch -D' docs"
  [ "$status" -eq 0 ]
}

@test "safe 2: rg -n literal reset pattern passes" {
  run probe 'rg -n "git reset --hard" agent-hooks'
  [ "$status" -eq 0 ]
}

@test "safe 3: rg -F literal push pattern passes" {
  run probe "rg -F 'git push --force' ."
  [ "$status" -eq 0 ]
}

@test "safe 4: rg literal clean pattern passes" {
  run probe "rg 'git clean -fd' tests"
  [ "$status" -eq 0 ]
}

@test "unsafe 1: git branch -D foo blocks" {
  run probe "git branch -D foo"
  [ "$status" -eq 2 ]
}

@test "unsafe 2: rg then git branch -D blocks" {
  run probe "rg x; git branch -D foo"
  [ "$status" -eq 2 ]
}

@test "unsafe 3: command substitution blocks" {
  run probe 'rg $(git branch -D foo) .'
  [ "$status" -eq 2 ]
}

@test "unsafe 4: backtick substitution blocks" {
  run probe 'rg `git reset --hard` .'
  [ "$status" -eq 2 ]
}

@test "unsafe 5: rg --pre blocks" {
  run probe "rg --pre 'git reset --hard' x ."
  [ "$status" -eq 2 ]
}

@test "unsafe 6: env-assignment prefix blocks" {
  run probe "RIPGREP_CONFIG_PATH=x rg 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 7: pipe into sh blocks" {
  run probe "rg 'git reset --hard' . | sh"
  [ "$status" -eq 2 ]
}

@test "unsafe 8: rg && git reset --hard blocks" {
  run probe "rg x && git reset --hard"
  [ "$status" -eq 2 ]
}

@test "unsafe 9: inherited ripgrep config blocks" {
  export RIPGREP_CONFIG_PATH="$BATS_TEST_TMPDIR/rg.conf"
  run probe "rg 'git reset --hard' ."
  unset RIPGREP_CONFIG_PATH
  [ "$status" -eq 2 ]
}

@test "unsafe 10: exported rg function blocks" {
  rg() { :; }
  export -f rg
  run probe "rg 'git reset --hard' ."
  unset -f rg
  [ "$status" -eq 2 ]
}

@test "unsafe 11: an unidentified rg executable blocks" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/rg"
  chmod +x "$BATS_TEST_TMPDIR/bin/rg"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run probe "rg 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 12: compact -zC2 flags block" {
  run probe "rg -zC2 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 13: compact -znC2 flags block" {
  run probe "rg -znC2 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 14: a spoofed ripgrep version does not establish trust" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "ripgrep 99.0.0 (spoofed)"\n' > "$BATS_TEST_TMPDIR/bin/rg"
  chmod +x "$BATS_TEST_TMPDIR/bin/rg"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run probe "rg 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 15: hostname-bin cannot execute a helper" {
  run probe "rg --hostname-bin 'git reset --hard' --hyperlink-format 'file://{host}{path}' x ."
  [ "$status" -eq 2 ]
}

@test "unsafe 16: post-pattern pre blocks" {
  run probe "rg 'git reset --hard' --pre helper ."
  [ "$status" -eq 2 ]
}

@test "unsafe 17: post-pattern hostname-bin blocks" {
  run probe "rg 'git reset --hard' --hostname-bin helper --hyperlink-format 'file://{host}{path}' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 18: quoted pre-pattern pre blocks" {
  run probe "rg '--pre' helper 'git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 19: quoted post-pattern pre blocks" {
  run probe "rg 'git reset --hard' '--pre' helper ."
  [ "$status" -eq 2 ]
}

@test "unsafe 20: a path glob cannot expand into options" {
  run probe "rg 'git reset --hard' *"
  [ "$status" -eq 2 ]
}

@test "unsafe 21: mixed quotes cannot conceal an option" {
  run probe "rg 'git reset --hard' ''--pre=helper"
  [ "$status" -eq 2 ]
}

@test "unsafe 22: a pattern-position pre option blocks" {
  run probe "rg '--pre=git reset --hard' ."
  [ "$status" -eq 2 ]
}

@test "unsafe 23: -F does not make a leading-dash pattern literal" {
  run probe "rg -F '--pre=git reset --hard' ."
  [ "$status" -eq 2 ]
}

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

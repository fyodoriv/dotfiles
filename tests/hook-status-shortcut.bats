#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/base" "$TEST_DIR/candidate"
  cp "$REPO_ROOT"/agent-hooks/*.sh "$TEST_DIR/base/"
  cp "$REPO_ROOT"/agent-hooks/*.sh "$TEST_DIR/candidate/"
  cp "$REPO_ROOT"/agent-hooks/*.jq "$TEST_DIR/base/"
  cp "$REPO_ROOT"/agent-hooks/*.jq "$TEST_DIR/candidate/"
  git -C "$REPO_ROOT" show origin/feat/chezmoi:agent-hooks/block-dangerous-git.sh > "$TEST_DIR/base/block-dangerous-git.sh"
  chmod +x "$TEST_DIR/base/block-dangerous-git.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

probe() {
  jq -nc --arg command "$2" '{tool_input:{command:$command},cwd:"/tmp"}' | "$1/block-dangerous-git.sh"
}

@test "literal status and complex syntax retain guard verdict and output" {
  local command expected_status expected_output
  for command in 'git status' 'git status --short' 'git status -s -b' \
    'git status --porcelain=v1' 'git status; echo done' \
    'git status $(printf x)' 'git status --unknown'; do
    run probe "$TEST_DIR/base" "$command"
    expected_status="$status" expected_output="$output"
    run probe "$TEST_DIR/candidate" "$command"
    [ "$status" -eq "$expected_status" ]
    [ "$output" = "$expected_output" ]
  done
}

@test "missing helper falls back to the original guard" {
  rm "$TEST_DIR/candidate/literal-status-only.sh"
  run probe "$TEST_DIR/base" 'git status --short'
  local expected_status="$status" expected_output="$output"
  run probe "$TEST_DIR/candidate" 'git status --short'
  [ "$status" -eq "$expected_status" ]
  [ "$output" = "$expected_output" ]
}

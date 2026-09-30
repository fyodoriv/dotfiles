#!/usr/bin/env bats
# Tests for git-safe — guards against destructive git commands in multi-agent repos

load test_helper

GIT_SAFE_CMD="$BATS_TEST_DIRNAME/../bin/git-safe"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_REPO="$TEST_DIR/repo"

  mkdir -p "$TEST_REPO"
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" commit --no-verify --allow-empty -m "chore: initial" --quiet

  export PATH="$BATS_TEST_DIRNAME/../bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "git-safe script exists and is executable" {
  [ -f "$GIT_SAFE_CMD" ]
  [ -x "$GIT_SAFE_CMD" ]
}

@test "git-safe uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$GIT_SAFE_CMD"
}

# ── Bypass ───────────────────────────────────────────────────────

@test "GIT_SAFE_BYPASS=1 passes through any command" {
  cd "$TEST_REPO"
  # Even in a multi-agent repo, bypass should work
  mkdir -p .orchestrator
  run env GIT_SAFE_BYPASS=1 "$GIT_SAFE_CMD" status
  [ "$status" -eq 0 ]
}

# ── Non-multi-agent repos pass through ───────────────────────────

@test "git reset --hard passes through in single-agent repo" {
  cd "$TEST_REPO"
  echo "test" > file.txt
  git -C "$TEST_REPO" add file.txt
  git -C "$TEST_REPO" commit --no-verify -m "chore: add file" --quiet
  echo "dirty" > file.txt

  run "$GIT_SAFE_CMD" reset --hard
  [ "$status" -eq 0 ]
  # File should be reset
  [ "$(cat file.txt)" = "test" ]
}

@test "git clean -fd passes through in single-agent repo" {
  cd "$TEST_REPO"
  echo "untracked" > untracked.txt

  run "$GIT_SAFE_CMD" clean -fd
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_REPO/untracked.txt" ]
}

@test "git checkout . passes through in single-agent repo" {
  cd "$TEST_REPO"
  echo "test" > file.txt
  git -C "$TEST_REPO" add file.txt
  git -C "$TEST_REPO" commit --no-verify -m "chore: add file" --quiet
  echo "dirty" > file.txt

  run "$GIT_SAFE_CMD" checkout .
  [ "$status" -eq 0 ]
}

# ── Multi-agent detection ────────────────────────────────────────

@test "detects multi-agent repo via .orchestrator directory" {
  cd "$TEST_REPO"
  mkdir -p .orchestrator
  run "$GIT_SAFE_CMD" reset --hard
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked destructive command"* ]]
}

@test "detects multi-agent repo via .worktrees directory" {
  cd "$TEST_REPO"
  mkdir -p .worktrees
  run "$GIT_SAFE_CMD" reset --hard
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked destructive command"* ]]
}

# ── Blocking in multi-agent repos ────────────────────────────────

make_multi_agent() {
  mkdir -p "$TEST_REPO/.orchestrator"
}

@test "blocks git reset --hard in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" reset --hard
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked destructive command"* ]]
  [[ "$output" == *"reset"* ]]
}

@test "blocks git reset --hard HEAD in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" reset --hard HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked"* ]]
}

@test "allows git reset --soft in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" reset --soft HEAD
  [ "$status" -eq 0 ]
}

@test "blocks git checkout . in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" checkout .
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked"* ]]
  [[ "$output" == *"checkout"* ]]
}

@test "allows git checkout -b new-branch in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" checkout -b test-branch
  [ "$status" -eq 0 ]
}

@test "allows git checkout branch-name in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  git -C "$TEST_REPO" checkout -b feature --quiet 2>/dev/null
  git -C "$TEST_REPO" checkout main --quiet
  run "$GIT_SAFE_CMD" checkout feature
  [ "$status" -eq 0 ]
}

@test "blocks git clean -fd in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" clean -fd
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked"* ]]
  [[ "$output" == *"clean"* ]]
}

@test "blocks git clean -f in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" clean -f
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked"* ]]
}

@test "blocks git clean -fdx in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" clean -fdx
  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked"* ]]
}

# ── Warnings (non-blocking) ─────────────────────────────────────

@test "warns on git add -A in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  echo "file" > new.txt
  run "$GIT_SAFE_CMD" add -A
  [ "$status" -eq 0 ]
  [[ "$output" == *"stages ALL changes"* ]]
}

@test "warns on git add . in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  echo "file" > new.txt
  run "$GIT_SAFE_CMD" add .
  [ "$status" -eq 0 ]
  [[ "$output" == *"stages ALL changes"* ]]
}

@test "warns on git add --all in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  echo "file" > new.txt
  run "$GIT_SAFE_CMD" add --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"stages ALL changes"* ]]
}

@test "no warning on git add specific-file in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  echo "file" > specific.txt
  run "$GIT_SAFE_CMD" add specific.txt
  [ "$status" -eq 0 ]
  [[ "$output" != *"stages ALL changes"* ]]
}

# ── Bypass hint in block message ─────────────────────────────────

@test "block message includes bypass instructions" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" reset --hard
  [ "$status" -eq 1 ]
  [[ "$output" == *"GIT_SAFE_BYPASS=1"* ]]
}

# ── Pass-through for safe commands ───────────────────────────────

@test "git status passes through in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" status
  [ "$status" -eq 0 ]
}

@test "git log passes through in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" log --oneline -1
  [ "$status" -eq 0 ]
}

@test "git diff passes through in multi-agent repo" {
  cd "$TEST_REPO"
  make_multi_agent
  run "$GIT_SAFE_CMD" diff
  [ "$status" -eq 0 ]
}

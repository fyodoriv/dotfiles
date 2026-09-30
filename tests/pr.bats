#!/usr/bin/env bats
# Tests for pr — commit, push, and create PR workflow

load test_helper

PR_CMD="$BATS_TEST_DIRNAME/../bin/pr"

setup() {
  TEST_DIR="$(mktemp -d)"

  # Create a bare remote repo
  REMOTE_REPO="$TEST_DIR/remote.git"
  git init --bare --quiet "$REMOTE_REPO"

  # Create a working repo cloned from the remote
  TEST_REPO="$TEST_DIR/repo"
  git clone --quiet "$REMOTE_REPO" "$TEST_REPO"
  git -C "$TEST_REPO" commit --no-verify --allow-empty -m "chore: initial" --quiet
  git -C "$TEST_REPO" push --quiet 2>/dev/null

  # Stub gh to avoid real GitHub API calls
  GH_STUB="$TEST_DIR/gh"
  cat > "$GH_STUB" << 'STUB'
#!/bin/bash
echo "[gh] $*"
STUB
  chmod +x "$GH_STUB"

  # Put stub at front of PATH
  export PATH="$TEST_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "pr script exists and is executable" {
  [ -f "$PR_CMD" ]
  [ -x "$PR_CMD" ]
}

@test "pr uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$PR_CMD"
}

# ── Branch guards ────────────────────────────────────────────────

@test "pr refuses to run on main branch" {
  cd "$TEST_REPO"
  run "$PR_CMD" "feat: something"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Can't create PR from main"* ]]
}

@test "pr refuses to run on master branch" {
  cd "$TEST_REPO"
  # Rename default branch to master
  git -C "$TEST_REPO" branch -m main master --quiet 2>/dev/null
  run "$PR_CMD" "feat: something"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Can't create PR from master"* ]]
}

# ── Commit message handling ──────────────────────────────────────

@test "pr uses provided title as commit message" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/test --quiet 2>/dev/null

  echo "new feature" > feature.txt
  git -C "$TEST_REPO" add feature.txt

  run "$PR_CMD" "feat: add login"
  [ "$status" -eq 0 ]

  # Verify commit was created with the provided title
  last_msg=$(git -C "$TEST_REPO" log -1 --pretty=%s)
  [ "$last_msg" = "feat: add login" ]
}

@test "pr falls back to last commit message when no title given" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/fallback --quiet 2>/dev/null

  # No uncommitted changes — title defaults to last commit message
  run "$PR_CMD"
  [ "$status" -eq 0 ]

  # gh should have been called with the last commit message as title
  [[ "$output" == *"chore: initial"* ]]
}

# ── Staging and committing ───────────────────────────────────────

@test "pr commits tracked changes before pushing" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/commit-test --quiet 2>/dev/null

  # Create and track a file, then modify it
  echo "v1" > tracked.txt
  git -C "$TEST_REPO" add tracked.txt
  git -C "$TEST_REPO" commit -m "chore: add tracked" --quiet

  echo "v2" > tracked.txt

  run "$PR_CMD" "fix: update tracked"
  [ "$status" -eq 0 ]

  # Should have committed the change
  last_msg=$(git -C "$TEST_REPO" log -1 --pretty=%s)
  [ "$last_msg" = "fix: update tracked" ]
}

@test "pr skips commit when working tree is clean" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/clean --quiet 2>/dev/null

  # No changes — should still push and create PR without error
  run "$PR_CMD" "feat: no changes"
  [ "$status" -eq 0 ]

  # Last commit should still be the initial one (no new commit)
  last_msg=$(git -C "$TEST_REPO" log -1 --pretty=%s)
  [ "$last_msg" = "chore: initial" ]
}

@test "pr leaves untracked-only changes untouched with clear output" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/untracked-only --quiet 2>/dev/null
  echo "scratch" > scratch.txt

  run "$PR_CMD" "feat: untracked only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tracked or staged changes to commit"* ]]
  [[ "$output" == *"untracked file(s) untouched"* ]]

  last_msg=$(git -C "$TEST_REPO" log -1 --pretty=%s)
  [ "$last_msg" = "chore: initial" ]
  [[ "$(git -C "$TEST_REPO" status --porcelain)" == "?? scratch.txt" ]]
}

@test "pr uses git add -u to avoid staging untracked files" {
  grep -q 'git add -u' "$PR_CMD"
}

# ── Push behavior ────────────────────────────────────────────────

@test "pr pushes feature branch to remote" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/push-test --quiet 2>/dev/null

  run "$PR_CMD" "feat: push test"
  [ "$status" -eq 0 ]

  # Branch should exist on the remote
  run git -C "$REMOTE_REPO" branch
  [[ "$output" == *"feat/push-test"* ]]
}

@test "pr resolves tracking remote for push" {
  grep -q 'git config "branch.*remote"' "$PR_CMD"
}

# ── gh integration ───────────────────────────────────────────────

@test "pr calls gh to create draft PR" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/gh-test --quiet 2>/dev/null

  run "$PR_CMD" "feat: gh draft"
  [ "$status" -eq 0 ]

  # Stub gh should have been called with pr create
  [[ "$output" == *"[gh] pr create"* ]]
  [[ "$output" == *"--draft"* ]]
}

@test "pr passes title to gh pr create" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feat/title-pass --quiet 2>/dev/null

  run "$PR_CMD" "feat: my custom title"
  [ "$status" -eq 0 ]

  [[ "$output" == *"my custom title"* ]]
}

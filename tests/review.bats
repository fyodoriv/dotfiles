#!/usr/bin/env bats
# Tests for review — PR checkout and review workflow

load test_helper

REVIEW_CMD="$BATS_TEST_DIRNAME/../bin/review"

setup() {
  TEST_DIR="$(mktemp -d)"

  # Stub gh to avoid real GitHub API calls
  GH_STUB="$TEST_DIR/gh"
  cat > "$GH_STUB" << 'STUB'
#!/bin/bash
echo "[gh] $*"
STUB
  chmod +x "$GH_STUB"

  export PATH="$TEST_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "review script exists and is executable" {
  [ -f "$REVIEW_CMD" ]
  [ -x "$REVIEW_CMD" ]
}

@test "review uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$REVIEW_CMD"
}

# ── No-args behavior ────────────────────────────────────────────

@test "review with no args lists open PRs and exits 0" {
  run "$REVIEW_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Open PRs"* ]]
  [[ "$output" == *"[gh] pr list"* ]]
}

@test "review with no args shows usage hint" {
  run "$REVIEW_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: review"* ]]
}

# ── PR checkout ──────────────────────────────────────────────────

@test "review with PR number calls gh pr checkout" {
  # Need a git repo for gh operations
  TEST_REPO="$TEST_DIR/repo"
  git init --quiet "$TEST_REPO"
  cd "$TEST_REPO"
  git commit --no-verify --allow-empty -m "init" --quiet

  run bash -c "echo 'n' | '$REVIEW_CMD' 123"
  [[ "$output" == *"[gh] pr checkout 123"* ]]
}

@test "review shows diff stats for the PR" {
  TEST_REPO="$TEST_DIR/repo"
  git init --quiet "$TEST_REPO"
  cd "$TEST_REPO"
  git commit --no-verify --allow-empty -m "init" --quiet

  run bash -c "echo 'n' | '$REVIEW_CMD' 456"
  [[ "$output" == *"[gh] pr diff 456 --stat"* ]]
}

@test "review shows Files changed section" {
  TEST_REPO="$TEST_DIR/repo"
  git init --quiet "$TEST_REPO"
  cd "$TEST_REPO"
  git commit --no-verify --allow-empty -m "init" --quiet

  run bash -c "echo 'n' | '$REVIEW_CMD' 789"
  [[ "$output" == *"Files changed"* ]]
}

# ── Test runner detection ────────────────────────────────────────

@test "review checks for package.json to detect test runner" {
  grep -q 'package.json' "$REVIEW_CMD"
}

@test "review supports npm test and yarn test" {
  grep -q 'npm test' "$REVIEW_CMD"
  grep -q 'yarn test' "$REVIEW_CMD"
}

# ── Browser integration ─────────────────────────────────────────

@test "review offers to open PR in browser" {
  grep -q 'gh pr view.*--web' "$REVIEW_CMD"
}

@test "review prints PR number in checkout message" {
  grep -q 'Checking out PR' "$REVIEW_CMD"
}

@test "review read commands have timeouts" {
  # All read commands should have -t for timeout to prevent hanging in CI
  while IFS= read -r line; do
    if echo "$line" | grep -q '^\s*read ' && ! echo "$line" | grep -q '\-t '; then
      fail "read command without timeout: $line"
    fi
  done < "$REVIEW_CMD"
}

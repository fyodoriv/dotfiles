#!/usr/bin/env bats
# Tests for hotfix — quick hotfix branch workflow

load test_helper

HOTFIX_CMD="$BATS_TEST_DIRNAME/../bin/hotfix"

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
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "hotfix script exists and is executable" {
  [ -f "$HOTFIX_CMD" ]
  [ -x "$HOTFIX_CMD" ]
}

@test "hotfix uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$HOTFIX_CMD"
}

# ── Argument validation ─────────────────────────────────────────

@test "hotfix with no args exits 1 and shows usage" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: hotfix"* ]]
}

# ── Branch creation ──────────────────────────────────────────────

@test "hotfix creates branch from main" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: resolve crash"
  [ "$status" -eq 0 ]

  branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  [[ "$branch" == hotfix/* ]]
}

@test "hotfix branch name is sanitized from message" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: resolve crash on startup"
  [ "$status" -eq 0 ]

  branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  # Runs of non-alphanumeric chars (e.g. ": ") collapse into a single
  # dash; lowercased. Exact form is pinned by docs/user-stories/07.
  [[ "$branch" == "hotfix/fix-resolve-crash-on-startup" ]]
}

@test "hotfix branch name matches story 07's documented example" {
  # Story 07 advertises that `hotfix "fix: resolve crash on startup"`
  # produces `hotfix/fix-resolve-crash-on-startup`. Pin the exact form
  # so any future regression in the sed slug logic fails CI.
  cd "$TEST_REPO"
  local doc_example_branch
  doc_example_branch=$(grep -oE 'hotfix/fix-resolve-crash-on-startup' \
    "$BATS_TEST_DIRNAME/../docs/user-stories/07-git-workflow-helpers.md" | head -1)
  [ -n "$doc_example_branch" ] || {
    echo "story 07 must document 'hotfix/fix-resolve-crash-on-startup' as the example branch"
    return 1
  }

  run "$HOTFIX_CMD" "fix: resolve crash on startup"
  [ "$status" -eq 0 ]
  branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  [ "$branch" = "$doc_example_branch" ] || {
    echo "drift: story 07 says branch is '$doc_example_branch' but hotfix produced '$branch'"
    echo "fix: align bin/hotfix sanitizer with the documented example"
    return 1
  }
}

@test "hotfix shows confirmation message" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: quick patch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"On branch:"* ]]
  [[ "$output" == *"hotfix/"* ]]
}

@test "hotfix shows pr command hint" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: quick patch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pr"* ]]
}

# ── Stash behavior ───────────────────────────────────────────────

@test "hotfix preserves uncommitted changes via stash" {
  cd "$TEST_REPO"
  echo "work in progress" > wip.txt

  run "$HOTFIX_CMD" "fix: urgent bug"
  [ "$status" -eq 0 ]

  # The WIP file should still be present after stash pop
  [ -f "$TEST_REPO/wip.txt" ]
  [[ "$(cat "$TEST_REPO/wip.txt")" == "work in progress" ]]
}

@test "hotfix works with no uncommitted changes" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: clean state"
  [ "$status" -eq 0 ]
  [[ "$output" == *"On branch:"* ]]
}

# ── Branch starts from main ─────────────────────────────────────

@test "hotfix switches to main before branching" {
  cd "$TEST_REPO"
  git -C "$TEST_REPO" checkout -b feature --quiet 2>/dev/null

  run "$HOTFIX_CMD" "fix: from feature branch"
  [ "$status" -eq 0 ]

  # Should be on hotfix branch, not feature
  branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  [[ "$branch" == hotfix/* ]]

  # Parent should be main
  main_sha=$(git -C "$TEST_REPO" rev-parse main)
  parent_sha=$(git -C "$TEST_REPO" rev-parse HEAD)
  [ "$main_sha" = "$parent_sha" ]
}

# ── Branch name length limit ────────────────────────────────────

@test "hotfix truncates long branch names to 50 chars" {
  cd "$TEST_REPO"
  run "$HOTFIX_CMD" "fix: this is a very long description that should be truncated to keep branch names reasonable"
  [ "$status" -eq 0 ]

  branch=$(git -C "$TEST_REPO" rev-parse --abbrev-ref HEAD)
  # "hotfix/" prefix (7 chars) + up to 50 chars from message
  suffix="${branch#hotfix/}"
  [ "${#suffix}" -le 50 ]
}

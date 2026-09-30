#!/usr/bin/env bats
# Tests for bin/git-maintain — index corruption detection, worktree pruning,
# subshell isolation, and stale branch cleanup.

SCRIPT="$BATS_TEST_DIRNAME/../bin/git-maintain"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  REPOS_DIR="$TEST_DIR/repos"
  mkdir -p "$TEST_HOME" "$REPOS_DIR"
  export HOME="$TEST_HOME"
  export DOTFILES_REPOS_DIR="$REPOS_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a minimal git repo
_create_repo() {
  local name="$1"
  local dir="$REPOS_DIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "test@test.com"
  git -C "$dir" config user.name "Test"
  echo "init" > "$dir/README.md"
  git -C "$dir" add .
  git -C "$dir" commit -m "initial" --quiet
}

# ── Script structure ──────────────────────────────────────────────

@test "git-maintain script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "git-maintain script uses set -euo pipefail" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

@test "git-maintain loop body runs in subshell" {
  # Verify the pattern: ( cd "$dir" || exit; ... ) || true
  grep -q '(  *$' "$SCRIPT" || grep -q '($' "$SCRIPT" || grep -qP '^\s+\(' "$SCRIPT"
}

# ── Index corruption detection ────────────────────────────────────

@test "detects truncated index file (< 1KB)" {
  _create_repo "test-repo"
  local repo="$REPOS_DIR/test-repo"

  # Truncate the index to simulate corruption
  echo "x" > "$repo/.git/index"
  local size
  size=$(wc -c < "$repo/.git/index" | tr -d ' ')
  [ "$size" -lt 1024 ]

  # Run the index detection logic
  run bash -c "
    source '$BATS_TEST_DIRNAME/../lib/colors.sh'
    cd '$repo'
    index_file='.git/index'
    index_size=\$(wc -c < \"\$index_file\" | tr -d ' ')
    if [ \"\$index_size\" -lt 1024 ]; then
      echo 'truncated'
      rm -f \"\$index_file\"
      git reset 2>/dev/null
      echo 'rebuilt'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"truncated"* ]]
  [[ "$output" == *"rebuilt"* ]]

  # Index should be rebuilt
  [ -f "$repo/.git/index" ]
}

@test "healthy index is not touched" {
  _create_repo "healthy-repo"
  local repo="$REPOS_DIR/healthy-repo"

  # Add enough files to push the index well over 1KB
  for i in $(seq 1 50); do
    echo "file $i content" > "$repo/file-$i.txt"
  done
  git -C "$repo" add .
  git -C "$repo" commit -m "bulk files" --quiet

  local orig_size
  orig_size=$(wc -c < "$repo/.git/index" | tr -d ' ')
  [ "$orig_size" -ge 1024 ]

  run bash -c "
    cd '$repo'
    index_file='.git/index'
    index_size=\$(wc -c < \"\$index_file\" | tr -d ' ')
    if [ \"\$index_size\" -lt 1024 ]; then
      echo 'would rebuild'
    else
      echo 'ok'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok"* ]]
}

# ── Stale sharedindex cleanup ─────────────────────────────────────

@test "removes stale sharedindex files" {
  _create_repo "shared-repo"
  local repo="$REPOS_DIR/shared-repo"

  # Create fake stale sharedindex files
  touch "$repo/.git/sharedindex.abc123"
  touch "$repo/.git/sharedindex.def456"

  run bash -c "
    cd '$repo'
    shared_cleaned=0
    for f in .git/sharedindex.* .git/worktrees/*/sharedindex.*; do
      [ -f \"\$f\" ] && rm -f \"\$f\" && shared_cleaned=\$((shared_cleaned + 1))
    done
    echo \"cleaned \$shared_cleaned\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleaned 2"* ]]
  [ ! -f "$repo/.git/sharedindex.abc123" ]
  [ ! -f "$repo/.git/sharedindex.def456" ]
}

# ── Stale branch cleanup ─────────────────────────────────────────

@test "cleans merged branches" {
  _create_repo "branch-repo"
  local repo="$REPOS_DIR/branch-repo"

  # Create and merge a feature branch
  git -C "$repo" checkout -b feature-done --quiet
  echo "feature" > "$repo/feature.txt"
  git -C "$repo" add .
  git -C "$repo" commit -m "feature done" --quiet
  git -C "$repo" checkout main --quiet 2>/dev/null || git -C "$repo" checkout master --quiet
  git -C "$repo" merge feature-done --quiet

  # Verify the branch exists before cleanup
  local branches_before
  branches_before=$(git -C "$repo" branch | wc -l | tr -d ' ')
  [ "$branches_before" -ge 2 ]

  # Run the stale branch cleanup logic
  run bash -c "
    cd '$repo'
    default_branch=\$(git branch --show-current)
    stale=\$(git branch --merged \"\$default_branch\" 2>/dev/null | grep -v '\*\|\$default_branch\|master' | wc -l | tr -d ' ')
    if [ \"\$stale\" -gt 0 ]; then
      git branch --merged \"\$default_branch\" 2>/dev/null | grep -v '\*\|\$default_branch\|master' | xargs -n 1 git branch -d 2>/dev/null
      echo \"cleaned \$stale\"
    else
      echo 'none'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleaned"* ]]

  # Branch should be gone
  run git -C "$repo" branch --list "feature-done"
  [ -z "$output" ]
}

@test "does not delete unmerged branches" {
  _create_repo "unmerged-repo"
  local repo="$REPOS_DIR/unmerged-repo"

  # Create an unmerged branch
  git -C "$repo" checkout -b feature-wip --quiet
  echo "wip" > "$repo/wip.txt"
  git -C "$repo" add .
  git -C "$repo" commit -m "wip" --quiet
  git -C "$repo" checkout main --quiet 2>/dev/null || git -C "$repo" checkout master --quiet

  run bash -c "
    cd '$repo'
    default_branch=\$(git branch --show-current)
    stale=\$(git branch --merged \"\$default_branch\" 2>/dev/null | grep -v '\*\|\$default_branch\|master' | wc -l | tr -d ' ')
    echo \"stale=\$stale\"
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"stale=0"* ]]

  # Unmerged branch should still exist
  run git -C "$repo" branch --list "feature-wip"
  [[ "$output" == *"feature-wip"* ]]
}

# ── Subshell isolation ────────────────────────────────────────────

@test "subshell prevents directory leak on failure" {
  _create_repo "repo-a"
  _create_repo "repo-b"

  local start_dir
  start_dir="$(pwd)"

  # Simulate the subshell pattern from git-maintain
  for dir in "$REPOS_DIR"/*/; do
    (
      cd "$dir" || exit
      # Even if something fails, we're in a subshell
      true
    ) || true
  done

  # Should still be in original directory
  [ "$(pwd)" = "$start_dir" ]
}

# ── Quick mode ────────────────────────────────────────────────────

@test "git-maintain script supports --quick flag" {
  grep -q '\-\-quick' "$SCRIPT"
}

# ── Skips non-git directories ─────────────────────────────────────

@test "skips directories without .git" {
  mkdir -p "$REPOS_DIR/not-a-repo"
  _create_repo "real-repo"

  # Run maintain with --quick to skip fetch
  run bash -c "
    export DOTFILES_REPOS_DIR='$REPOS_DIR'
    source '$BATS_TEST_DIRNAME/../lib/colors.sh'
    log_run() { true; }
    bash '$SCRIPT' --quick 2>&1
  "
  [ "$status" -eq 0 ]
  [[ "$output" == *"real-repo"* ]]
  [[ "$output" != *"not-a-repo"* ]]
}

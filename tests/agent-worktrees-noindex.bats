#!/usr/bin/env bats
# Tests for lib/agent-worktrees-noindex.sh: the agent worktree folder becomes
# a symlink to a .noindex folder, which Spotlight skips.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  unset DOTFILES_AGENT_WORKTREES_DIR
  export DOTFILES_REPOS_DIR="$HOME/apps"
  mkdir -p "$HOME/apps/tooling"
  WT="$HOME/apps/tooling/wt"
  # shellcheck source=../lib/agent-worktrees-noindex.sh
  source "$BATS_TEST_DIRNAME/../lib/agent-worktrees-noindex.sh"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "agent_worktrees_dir defaults to the tooling wt folder" {
  [ "$(agent_worktrees_dir)" = "$WT" ]
}

@test "a real wt folder is not Spotlight-skipped" {
  mkdir -p "$WT"
  run agent_worktrees_noindexed
  [ "$status" -ne 0 ]
}

@test "fix creates wt as a symlink to wt.noindex when wt is absent" {
  agent_worktrees_noindex_fix
  [ -L "$WT" ]
  [ "$(readlink "$WT")" = "wt.noindex" ]
  [ -d "$WT.noindex" ]
  agent_worktrees_noindexed
}

@test "fix moves existing worktrees into wt.noindex and keeps their wt paths" {
  mkdir -p "$WT/feature-a"
  echo keep > "$WT/feature-a/file.txt"
  agent_worktrees_noindex_fix
  [ -L "$WT" ]
  [ "$(cat "$WT/feature-a/file.txt")" = keep ]
  [ -f "$WT.noindex/feature-a/file.txt" ]
  agent_worktrees_noindexed
}

@test "existing git worktrees still work through the wt symlink" {
  repo="$TEST_DIR/repo"
  git init --quiet "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com commit --quiet --allow-empty -m init
  mkdir -p "$WT"
  git -C "$repo" worktree add --quiet "$WT/feature-b" -b feature-b
  agent_worktrees_noindex_fix
  run git -C "$WT/feature-b" status --short --branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-b"* ]]
  run git -C "$repo" worktree list
  [ "$status" -eq 0 ]
  [[ "$output" != *"prunable"* ]]
}

@test "fix is a no-op when wt already points to wt.noindex" {
  agent_worktrees_noindex_fix
  touch "$WT/marker"
  agent_worktrees_noindex_fix
  [ -f "$WT.noindex/marker" ]
}

@test "fix refuses to merge a real wt folder into an existing wt.noindex" {
  mkdir -p "$WT/a" "$WT.noindex/b"
  run agent_worktrees_noindex_fix
  [ "$status" -ne 0 ]
  [ -d "$WT/a" ] && [ ! -L "$WT" ]
  [ -d "$WT.noindex/b" ]
}

@test "fix leaves a symlink to another folder alone" {
  mkdir -p "$TEST_DIR/elsewhere"
  ln -s "$TEST_DIR/elsewhere" "$WT"
  run agent_worktrees_noindex_fix
  [ "$status" -ne 0 ]
  [ "$(readlink "$WT")" = "$TEST_DIR/elsewhere" ]
}

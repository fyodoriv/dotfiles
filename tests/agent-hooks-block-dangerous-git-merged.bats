#!/usr/bin/env bats
# Issue #376: the force-delete flag on a local branch is allowed only for a
# branch proven merged (merged PR head, or its diff already on the default
# branch). Everything else stays blocked.

setup() {
  HOOK="${HOOK_UNDER_TEST:-$BATS_TEST_DIRNAME/../agent-hooks/block-dangerous-git.sh}"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q --bare -b main "$ORIGIN"
  git clone -q "$ORIGIN" "$REPO" 2>/dev/null
  cd "$REPO"
  git checkout -q -b main
  printf 'one\ntwo\nthree\n' > a.txt
  git add a.txt
  git commit -q -m base
  git push -q origin main
  git remote set-head origin main >/dev/null

  # gh stub: prints the SHA in $STUB_GH_OUT (empty = no merged PR).
  GH_STUB="$BATS_TEST_TMPDIR/gh"
  printf '#!/bin/bash\nprintf "%%s" "${STUB_GH_OUT:-}"\n' > "$GH_STUB"
  chmod +x "$GH_STUB"
  export DOTFILES_GH="$GH_STUB"
}

# Two-commit feature branch touching b.txt; leaves HEAD on main.
make_feature_branch() {
  git checkout -q -b "$1"
  printf 'x\n' > b.txt
  git add b.txt && git commit -q -m "$1 part 1"
  printf 'x\ny\n' > b.txt
  git add b.txt && git commit -q -m "$1 part 2"
  git checkout -q main
}

run_hook() {
  local cmd="$1"
  run bash -c 'jq -n --arg c "$1" --arg d "$2" "{cwd:\$d, tool_input:{command:\$c}}" | "$3"' _ "$cmd" "$REPO" "$HOOK"
}

@test "allows force-delete when the branch tip is the head of a merged PR" {
  make_feature_branch feat/merged-pr
  # Squash merge: one new commit on main, branch commits never reach main.
  git merge -q --squash feat/merged-pr && git commit -q -m "squash feat/merged-pr"
  # Alter the squash so only the PR check can prove it (different diff on main).
  printf 'extra\n' >> a.txt && git commit -q -am "later change"
  git checkout -q -b other
  export STUB_GH_OUT="$(git rev-parse feat/merged-pr)"
  run_hook "git branch -D feat/merged-pr"
  [ "$status" -eq 0 ]
}

@test "allows force-delete when the branch diff is already on the default branch" {
  make_feature_branch feat/squashed
  git merge -q --squash feat/squashed && git commit -q -m "squash feat/squashed"
  git push -q origin main
  unset STUB_GH_OUT
  # Not an ancestor: only the patch-id check can prove it.
  ! git merge-base --is-ancestor feat/squashed main
  run_hook "git branch -D feat/squashed"
  [ "$status" -eq 0 ]
}

@test "still blocks force-delete for a branch with unmerged work" {
  make_feature_branch feat/unmerged
  unset STUB_GH_OUT
  run_hook "git branch -D feat/unmerged"
  [ "$status" -eq 2 ]
  [ "$output" = "BLOCKED: 'git branch -D' is not permitted. Ask the user to run it manually." ]
}

@test "blocks when a merged PR head differs from the branch tip" {
  make_feature_branch feat/moved
  export STUB_GH_OUT="0000000000000000000000000000000000000000"
  run_hook "git branch -D feat/moved"
  [ "$status" -eq 2 ]
}

@test "blocks when one of several branches is unmerged" {
  make_feature_branch feat/ok
  make_feature_branch feat/bad
  git merge -q --squash feat/ok && git commit -q -m "squash ok"
  unset STUB_GH_OUT
  run_hook "git branch -D feat/ok feat/bad"
  [ "$status" -eq 2 ]
}

@test "blocks a merged-branch delete chained with another blocked command" {
  make_feature_branch feat/chain
  git merge -q --squash feat/chain && git commit -q -m "squash chain"
  unset STUB_GH_OUT
  run_hook "git branch -D feat/chain && git clean -fd"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git clean -f"* ]]
}

@test "blocks a branch name with shell expansion" {
  unset STUB_GH_OUT
  run_hook 'git branch -D $(git branch --show-current)'
  [ "$status" -eq 2 ]
}

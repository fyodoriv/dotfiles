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

  # Timeout shim, so the tests do not depend on gtimeout being installed.
  TMO_SHIM="$BATS_TEST_TMPDIR/tmo"
  cat > "$TMO_SHIM" <<'SHIM'
#!/bin/bash
t="$1"; shift
"$@" & p=$!
( sleep "$t"; kill -9 "$p" 2>/dev/null ) & w=$!
wait "$p"; rc=$?
kill "$w" 2>/dev/null
exit $rc
SHIM
  chmod +x "$TMO_SHIM"
  export DOTFILES_TIMEOUT_BIN="$TMO_SHIM"
}

# Two-commit feature branch touching b.txt; leaves HEAD on main.
make_feature_branch() {
  git checkout -q -b "$1"
  local f="${1//\//_}.txt"
  printf 'x\n' > "$f"
  git add "$f" && git commit -q -m "$1 part 1"
  printf 'x\ny\n' > "$f"
  git add "$f" && git commit -q -m "$1 part 2"
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

# Review findings on PR 385: every occurrence counts, and the proof must run in
# the folder the command acts on.

merged_and_unmerged() {
  make_feature_branch feat/m
  make_feature_branch feat/u
  git merge -q --squash feat/m && git commit -q -m "squash m"
  git push -q origin main
  unset STUB_GH_OUT
}

@test "blocks a second force-delete after a semicolon" {
  merged_and_unmerged
  run_hook "git branch -D feat/m; git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "blocks a second force-delete after &&" {
  merged_and_unmerged
  run_hook "git branch -D feat/m && git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "blocks a second force-delete on the next line" {
  merged_and_unmerged
  run_hook "git branch -D feat/m"$'\n'"git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "blocks a force-delete that follows a cd" {
  merged_and_unmerged
  run_hook "cd /tmp && git branch -D feat/m"
  [ "$status" -eq 2 ]
}

@test "blocks a force-delete that follows an env assignment" {
  merged_and_unmerged
  run_hook "GIT_DIR=$REPO/.git git branch -D feat/m"
  [ "$status" -eq 2 ]
}

@test "blocks a merged force-delete chained with any later command (fail closed)" {
  merged_and_unmerged
  run_hook "git branch -D feat/m && git status"
  [ "$status" -eq 2 ]
  run_hook "git branch -D feat/m && git -C . branch -D feat/u"
  [ "$status" -eq 2 ]
}

# Fourth review round on PR 385.

@test "blocks brace expansion in the branch word" {
  merged_and_unmerged
  run_hook "git branch -D {feat/m,feat/u}"
  [ "$status" -eq 2 ]
  # The reviewer's probe: one name is a real merged branch, the braces hide more.
  git branch atmain2 origin/main
  run_hook "git branch -D {atmain2,feat/u}"
  [ "$status" -eq 2 ]
}

@test "blocks revision syntax and other names outside the allow list" {
  merged_and_unmerged
  run_hook 'git branch -D main@{0}'
  [ "$status" -eq 2 ]
  run_hook 'git branch -D feat/m^'
  [ "$status" -eq 2 ]
  run_hook 'git branch -D HEAD'
  [ "$status" -eq 2 ]
}

@test "blocks when origin/HEAD is forged to point at a local branch" {
  merged_and_unmerged
  git symbolic-ref refs/remotes/origin/HEAD refs/heads/feat/u
  run_hook "git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "blocks when the default branch carries the name of the branch to delete" {
  merged_and_unmerged
  git update-ref refs/remotes/origin/feat/u "$(git rev-parse feat/u)"
  git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/feat/u
  run_hook "git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "matches git branch in any letter case" {
  merged_and_unmerged
  run_hook "GIT branch -D feat/u"
  [ "$status" -eq 2 ]
  run_hook "Git Branch -D feat/u"
  [ "$status" -eq 2 ]
  # A merged branch is checked like any other, whatever the letter case.
  run_hook "GIT branch -D feat/m"
  [ "$status" -eq 0 ]
}

@test "local proofs run first and gh time is capped for the whole command" {
  merged_and_unmerged
  make_feature_branch feat/x1
  make_feature_branch feat/x2
  make_feature_branch feat/x3
  printf '#!/bin/bash\nexec sleep 30\n' > "$GH_STUB"
  export DOTFILES_GH_TIMEOUT=10 DOTFILES_GH_BUDGET=3
  SECONDS=0
  run_hook "git branch -D feat/x1 feat/x2 feat/x3"
  [ "$status" -eq 2 ]
  [ "$SECONDS" -lt 9 ]
}

@test "a branch proven by the local proof never calls gh" {
  merged_and_unmerged
  printf '#!/bin/bash\ntouch "%s"\n' "$BATS_TEST_TMPDIR/gh-called" > "$GH_STUB"
  run_hook "git branch -D feat/m"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/gh-called" ]
}

# Second review round on PR 385.

@test "blocks a backslash-newline continuation that hides a second branch" {
  merged_and_unmerged
  run_hook "git branch -D feat/m \\"$'\n'"feat/u"
  [ "$status" -eq 2 ]
}

@test "blocks a backslash anywhere in the branch arguments" {
  merged_and_unmerged
  run_hook 'git branch -D feat/m\ x'
  [ "$status" -eq 2 ]
}

@test "allows a merged force-delete with a trailing 2>&1" {
  merged_and_unmerged
  run_hook "git branch -D feat/m 2>&1"
  [ "$status" -eq 0 ]
}

@test "allows a merged force-delete with a trailing 2>/dev/null" {
  merged_and_unmerged
  run_hook "git branch -D feat/m 2>/dev/null"
  [ "$status" -eq 0 ]
}

@test "a redirect does not hide an unmerged branch" {
  merged_and_unmerged
  run_hook "git branch -D feat/m 2>&1 feat/u"
  [ "$status" -eq 2 ]
}

@test "still blocks a redirect to a real file" {
  merged_and_unmerged
  run_hook "git branch -D feat/m 2>$BATS_TEST_TMPDIR/err"
  [ "$status" -eq 2 ]
}

@test "known gap: a command before the delete is blocked (fail closed)" {
  merged_and_unmerged
  run_hook "git checkout main && git branch -D feat/m"
  [ "$status" -eq 2 ]
}

@test "fails closed when the working folder is not a git repo" {
  merged_and_unmerged
  REPO="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$REPO"
  run_hook "git branch -D feat/m"
  [ "$status" -eq 2 ]
}

@test "missing gh falls back to the local proof, and fails closed without it" {
  merged_and_unmerged
  export DOTFILES_GH="$BATS_TEST_TMPDIR/no-such-gh"
  run_hook "git branch -D feat/m"
  [ "$status" -eq 0 ]
  git checkout -q -b feat/pr-only
  printf 'only\n' > only.txt && git add only.txt && git commit -q -m only
  git checkout -q main
  run_hook "git branch -D feat/pr-only"
  [ "$status" -eq 2 ]
}

# Third review round on PR 385.

@test "blocks a redirect glued to the branch name (feat/m2>&1 is branch m2)" {
  merged_and_unmerged
  make_feature_branch feat/m2
  run_hook "git branch -D feat/m2>&1"
  [ "$status" -eq 2 ]
  run_hook "git branch -D feat/m2>/dev/null"
  [ "$status" -eq 2 ]
  run_hook "git branch -D feat/m2 2>&1"
  [ "$status" -eq 2 ]
}

@test "without a timeout binary the PR proof is skipped, not run unbounded" {
  merged_and_unmerged
  git checkout -q -b feat/pr-only3
  printf 'only3\n' > only3.txt && git add only3.txt && git commit -q -m only3
  git checkout -q main
  export STUB_GH_OUT="$(git rev-parse feat/pr-only3)"
  printf '#!/bin/bash\ntrap "" ALRM\ntouch "%s"\nexec sleep 30\n' "$BATS_TEST_TMPDIR/gh-ran" > "$GH_STUB"
  export DOTFILES_TIMEOUT_BIN=""
  SECONDS=0
  run_hook "git branch -D feat/pr-only3"
  [ "$status" -eq 2 ]
  [ "$SECONDS" -lt 10 ]
  [ ! -e "$BATS_TEST_TMPDIR/gh-ran" ]
  # The local diff proof still decides without gh.
  run_hook "git branch -D feat/m"
  [ "$status" -eq 0 ]
}

@test "the merged-PR proof is limited to PRs into the default branch" {
  merged_and_unmerged
  git checkout -q -b feat/pr-only4
  printf 'only4\n' > only4.txt && git add only4.txt && git commit -q -m only4
  git checkout -q main
  export STUB_GH_OUT="$(git rev-parse feat/pr-only4)"
  export ARGS_FILE="$BATS_TEST_TMPDIR/gh-args"
  cat > "$GH_STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$ARGS_FILE"
case "$*" in *"--base main"*) printf '%s' "$STUB_GH_OUT" ;; esac
STUB
  run_hook "git branch -D feat/pr-only4"
  [ "$status" -eq 0 ]
  grep -q -- '--base main' "$ARGS_FILE"
}

@test "a branch name that looks like a glob is not expanded" {
  merged_and_unmerged
  run_hook "git branch -D feat/*"
  [ "$status" -eq 2 ]
}

@test "a hung gh times out and the hook fails closed" {
  merged_and_unmerged
  printf '#!/bin/bash\nexec sleep 30\n' > "$GH_STUB"
  export DOTFILES_GH_TIMEOUT=1
  git checkout -q -b feat/pr-only2
  printf 'only2\n' > only2.txt && git add only2.txt && git commit -q -m only2
  git checkout -q main
  SECONDS=0
  run_hook "git branch -D feat/pr-only2"
  [ "$status" -eq 2 ]
  [ "$SECONDS" -lt 15 ]
}

# Task block-dangerous-git-dash-c-bypass: parse the subcommand, not the text.

run_hook_in() {
  local dir="$1" cmd="$2"
  run bash -c 'jq -n --arg c "$1" --arg d "$2" "{cwd:\$d, tool_input:{command:\$c}}" | "$3"' _ "$cmd" "$dir" "$HOOK"
}

@test "git -C <repo> blocks an unmerged branch and allows a merged one" {
  merged_and_unmerged
  run_hook_in "$BATS_TEST_TMPDIR" "git -C $REPO branch -D feat/u"
  [ "$status" -eq 2 ]
  run_hook_in "$BATS_TEST_TMPDIR" "git -C $REPO branch -D feat/m"
  [ "$status" -eq 0 ]
}

@test "git --git-dir=<repo>/.git blocks an unmerged branch and allows a merged one" {
  merged_and_unmerged
  run_hook_in "$BATS_TEST_TMPDIR" "git --git-dir=$REPO/.git branch -D feat/u"
  [ "$status" -eq 2 ]
  run_hook_in "$BATS_TEST_TMPDIR" "git --git-dir=$REPO/.git branch -D feat/m"
  [ "$status" -eq 0 ]
  run_hook_in "$BATS_TEST_TMPDIR" "git --git-dir $REPO/.git branch -D feat/u"
  [ "$status" -eq 2 ]
}

@test "git -c and unknown global options before branch fail closed" {
  merged_and_unmerged
  run_hook "git -c core.x=y branch -D feat/m"
  [ "$status" -eq 2 ]
  run_hook "git --exec-path=/tmp branch -D feat/m"
  [ "$status" -eq 2 ]
}

@test "other spellings of the force-delete are checked, not ignored" {
  merged_and_unmerged
  for c in "git branch -d -f feat/u" "git branch --delete --force feat/u" \
           "git branch -fd feat/u" "git branch -df feat/u" "git branch feat/u -D" \
           "git  branch  -D  feat/u" "git branch -D -f feat/u"; do
    run_hook "$c"
    [ "$status" -eq 2 ]
  done
  for c in "git branch -d -f feat/m" "git branch --delete --force feat/m" \
           "git branch -fd feat/m" "git branch feat/m -D" "git  branch  -D  feat/m"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
  done
}

@test "glued letters after the flag are not branch names (-Dr, -Df)" {
  merged_and_unmerged
  git branch r feat/m
  run_hook "git branch -Dr r"
  [ "$status" -eq 2 ]
  run_hook "git branch -rD r"
  [ "$status" -eq 2 ]
  run_hook "git branch -Dx feat/m"
  [ "$status" -eq 2 ]
}

@test "ordinary git branch commands are not blocked" {
  merged_and_unmerged
  for c in "git branch" "git branch -a" "git branch -r" "git branch newb" \
           "git branch -d feat/m" "git -C $REPO branch -m old new" \
           "git commit -m 'branch only'" "git log --oneline"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
  done
}

@test "a gh answer over 64 KB still proves the merged PR" {
  make_feature_branch feat/big
  # The squash commit differs from the branch diff, so only the PR proof applies.
  git merge -q --squash feat/big
  printf 'tweak\n' >> a.txt && git add a.txt
  git commit -q -m "squash feat/big with a tweak"
  git push -q origin main
  tip="$(git rev-parse feat/big)"
  printf '#!/bin/bash\nprintf "%%s\\n" "%s"\nyes abcdefghijklmnopqrstuvwxyz | head -n 20000\n' "$tip" > "$GH_STUB"
  run_hook "git branch -D feat/big"
  [ "$status" -eq 0 ]
}

@test "default-branch fingerprints are computed once for many branches" {
  local names="" n
  for n in 1 2 3 4 5; do
    make_feature_branch feat/s$n
    git merge -q --squash feat/s$n && git commit -q -m "squash s$n"
    names="$names feat/s$n"
  done
  git push -q origin main
  # GIT_TRACE lists every git command the hook runs; count the history walks.
  GIT_TRACE="$BATS_TEST_TMPDIR/trace" run_hook "git branch -D$names"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'git log -n 200' "$BATS_TEST_TMPDIR/trace")" -eq 1 ]
}

# Review of the parsed match: quoting, long-option prefixes, in-command aliases.

@test "quoted, escaped or path-qualified words do not hide a force-delete" {
  merged_and_unmerged
  for c in "\\git branch -d -f feat/u" "/usr/bin/git branch -d -f feat/u" \
           "'git' branch -D feat/u" "\"git\" branch -D feat/u" \
           "g''it branch -D feat/u" "git 'branch' -d -f feat/u" \
           "git \\branch -d -f feat/u" "git branch -d '-f' feat/u" \
           "git branch -d \"\"-f feat/u"; do
    run_hook "$c"
    [ "$status" -eq 2 ]
  done
}

@test "shortened long options are read as --delete and --force" {
  merged_and_unmerged
  run_hook "git branch --del --force feat/u"
  [ "$status" -eq 2 ]
  run_hook "git branch -d --forc feat/u"
  [ "$status" -eq 2 ]
  run_hook "git branch --de --force feat/u"
  [ "$status" -eq 2 ]
  run_hook "git branch --d --force feat/u"
  [ "$status" -eq 2 ]
  run_hook "git branch --de --forc feat/u"
  [ "$status" -eq 2 ]
  # A merged branch is still allowed with the shortened spelling.
  run_hook "git branch --del --force feat/m"
  [ "$status" -eq 0 ]
  run_hook "git branch --de --forc feat/m"
  [ "$status" -eq 0 ]
}

@test "an in-command git alias cannot hide the branch subcommand" {
  merged_and_unmerged
  run_hook "git -c alias.b=branch b -D feat/u"
  [ "$status" -eq 2 ]
  run_hook "AB=branch git --config-env alias.b=AB b -D feat/u"
  [ "$status" -eq 2 ]
  run_hook "git --config-env=alias.b=AB b -D feat/u"
  [ "$status" -eq 2 ]
}

@test "global options on other git commands are not blocked" {
  merged_and_unmerged
  for c in "git -c core.pager=cat log --oneline" "git --no-pager branch" \
           "git -C $REPO status" "git --git-dir=$REPO/.git log"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
  done
}

# Task git-ref-delete-other-commands: the other commands that destroy a branch,
# and the spellings the shell rewrites before git runs.

@test "update-ref -d on a branch: unmerged blocks, merged passes" {
  merged_and_unmerged
  run_hook 'git update-ref -d refs/heads/feat/u'
  [ "$status" -eq 2 ]
  run_hook 'git update-ref -d refs/heads/feat/m'
  [ "$status" -eq 0 ]
  run_hook "git -C $REPO update-ref -d refs/heads/feat/u"
  [ "$status" -eq 2 ]
}

@test "update-ref on other refs keeps working" {
  merged_and_unmerged
  git tag v1
  run_hook 'git update-ref -d refs/tags/v1'
  [ "$status" -eq 0 ]
  run_hook 'git update-ref refs/stash HEAD'
  [ "$status" -eq 0 ]
  run_hook 'git update-ref -d refs/notes/x'
  [ "$status" -eq 0 ]
}

@test "update-ref cannot forge a remote-tracking ref or hide refs in stdin" {
  merged_and_unmerged
  run_hook 'git update-ref refs/remotes/origin/main feat/u'
  [ "$status" -eq 2 ]
  run_hook 'git update-ref --stdin'
  [ "$status" -eq 2 ]
}

@test "push to the local repo with an empty source deletes a branch" {
  merged_and_unmerged
  run_hook 'git push . :feat/u'
  [ "$status" -eq 2 ]
  run_hook 'git push . :refs/heads/feat/u'
  [ "$status" -eq 2 ]
  run_hook 'git push . :feat/m'
  [ "$status" -eq 0 ]
  run_hook 'git push . feat/m:feat/u'
  [ "$status" -eq 2 ]
}

@test "ordinary pushes are not blocked" {
  merged_and_unmerged
  for c in 'git push origin main' 'git push -u origin feat/u' 'git push --force-with-lease origin feat/u'; do
    run_hook "$c"
    [ "$status" -eq 0 ]
  done
}

@test "branch -M over an unmerged branch blocks, over a merged one passes" {
  merged_and_unmerged
  run_hook 'git branch -M feat/m feat/u'
  [ "$status" -eq 2 ]
  run_hook 'git branch -M feat/u feat/m'
  [ "$status" -eq 0 ]
  run_hook 'git branch -M brand-new'
  [ "$status" -eq 0 ]
  run_hook 'git branch -m -f feat/m feat/u'
  [ "$status" -eq 2 ]
}

@test "branch -f over an unmerged branch blocks, over a merged one passes" {
  merged_and_unmerged
  run_hook 'git branch -f feat/u main'
  [ "$status" -eq 2 ]
  run_hook 'git branch -f feat/m main'
  [ "$status" -eq 0 ]
  run_hook 'git branch -f does-not-exist main'
  [ "$status" -eq 0 ]
  run_hook 'git branch --force feat/u main'
  [ "$status" -eq 2 ]
}

@test "spellings the shell rewrites before git runs block" {
  merged_and_unmerged
  for c in "\$'git' branch -D feat/u" "\$'\\x67it' branch -D feat/u" \
           "git branch \$'-D' feat/u" '`echo git` branch -D feat/u' \
           '$(echo git) branch -D feat/u' '/usr/bin/gi? branch -D feat/u' \
           'git branch ${x:--D} feat/u' '$(echo git) update-ref -d refs/heads/feat/u' \
           'git branch -f feat/u $(echo main)' \
           "git \$'branch' -D feat/u" "git \$'update-ref' -d refs/heads/feat/u" \
           'git $(echo branch) -D feat/u' 'git `echo branch` -D feat/u'; do
    run_hook "$c"
    [ "$status" -eq 2 ]
  done
}

@test "command substitution that only reads a branch is not blocked" {
  merged_and_unmerged
  for c in 'echo $(git branch --show-current)' 'git branch --contains $(git rev-parse HEAD)' \
           'git push origin "$B"' 'git branch -a' 'git branch --list ${x}' \
           'git branch --contains ${x}' 'git $(echo log) --oneline'; do
    run_hook "$c"
    [ "$status" -eq 0 ]
  done
}

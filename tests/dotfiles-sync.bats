#!/usr/bin/env bats
# Tests for dotfiles-sync — auto-commit, push, and pull dotfiles changes.
# Runs via LaunchAgent; exercises git operations in isolated repos.

load test_helper

SYNC_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-sync"

# Opt in to within-file parallelism — overrides the global
# `--no-parallelize-within-files` set in the Makefile. Each test creates
# its own TEST_DIR via mktemp and only writes inside it. dotfiles-sync.bats
# is the longest single file (~92s serial); within-file parallelism cuts
# its wall time to ~12s under 16-job parallelism, eliminating it as the
# suite's bottleneck.
setup_file() {
  unset BATS_NO_PARALLELIZE_WITHIN_FILE
  # Build the template repo once — each test gets a fast cp -r copy
  export FILE_TMPDIR="$BATS_FILE_TMPDIR"
  local tmpl="$FILE_TMPDIR/template"
  mkdir -p "$tmpl"

  # Create a bare remote repo
  git init --bare --quiet "$tmpl/remote.git"

  # Create a working repo with remote
  git init --quiet "$tmpl/dotfiles"
  mkdir -p "$tmpl/dotfiles/bin" "$tmpl/dotfiles/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-sync" "$tmpl/dotfiles/bin/dotfiles-sync"
  chmod +x "$tmpl/dotfiles/bin/dotfiles-sync"
  cp "$BATS_TEST_DIRNAME/../lib/colors.sh" "$tmpl/dotfiles/lib/colors.sh"
  cp "$BATS_TEST_DIRNAME/../lib/stats.sh" "$tmpl/dotfiles/lib/stats.sh"
  cp "$BATS_TEST_DIRNAME/../lib/lock.sh" "$tmpl/dotfiles/lib/lock.sh"
  cp "$BATS_TEST_DIRNAME/../lib/push-error-classify.sh" "$tmpl/dotfiles/lib/push-error-classify.sh"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh" "$tmpl/dotfiles/lib/agentbrew-locate.sh"

  git -C "$tmpl/dotfiles" add -A
  git -C "$tmpl/dotfiles" commit --no-verify -m "chore: initial" --quiet
  git -C "$tmpl/dotfiles" remote add origin "$tmpl/remote.git"
  git -C "$tmpl/dotfiles" push --quiet -u origin "$(git -C "$tmpl/dotfiles" branch --show-current)" 2>/dev/null
  # Set origin/HEAD so dotfiles-sync's branch-gate can resolve the canonical
  # branch. A real `git clone` sets this automatically; init + push does not.
  git -C "$tmpl/dotfiles" remote set-head origin "$(git -C "$tmpl/dotfiles" branch --show-current)" 2>/dev/null || true
}

setup() {
  TEST_DIR="$(mktemp -d)"

  # Fast copy from template (avoids git init + commit per test)
  cp -r "$FILE_TMPDIR/template/remote.git" "$TEST_DIR/remote.git"
  cp -r "$FILE_TMPDIR/template/dotfiles" "$TEST_DIR/dotfiles"

  REMOTE_REPO="$TEST_DIR/remote.git"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  # Fix remote URL to point to this test's copy
  git -C "$TEST_DOTFILES" remote set-url origin "$REMOTE_REPO"

  # Isolate HOME
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  unset DOTFILES_REPOS_DIR
  git config --global user.email "test@test.com"
  git config --global user.name "Test"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Script basics ────────────────────────────────────────────────

@test "sync script exists and is executable" {
  [ -f "$SYNC_CMD" ]
  [ -x "$SYNC_CMD" ]
}

@test "sync uses set -euo pipefail" {
  grep -q 'set -euo pipefail' "$SYNC_CMD"
}

@test "sync sources stats.sh" {
  grep -q 'source.*lib/stats.sh' "$SYNC_CMD"
}

# ── No changes ───────────────────────────────────────────────────

@test "sync with no local changes reports no changes" {
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No changes"* ]]
}

@test "sync with no changes still logs run" {
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [ -f "$DOTFILES_STATS_FILE" ]
  grep -q '"task":"sync"' "$DOTFILES_STATS_FILE"
}

# ── Auto-commit and push ────────────────────────────────────────

@test "sync commits local changes" {
  echo "new config" > "$TEST_DOTFILES/some.conf"
  git -C "$TEST_DOTFILES" add some.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]

  # Working tree should be clean after sync
  [ -z "$(git -C "$TEST_DOTFILES" status --porcelain)" ]
}

@test "sync commit message matches expected format" {
  echo "config" > "$TEST_DOTFILES/test.conf"
  git -C "$TEST_DOTFILES" add test.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]

  last_msg=$(git -C "$TEST_DOTFILES" log -1 --format='%s')
  [[ "$last_msg" == sync:\ auto-update\ * ]]
}

@test "sync pushes changes to remote" {
  echo "pushed" > "$TEST_DOTFILES/pushed.conf"
  git -C "$TEST_DOTFILES" add pushed.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]

  # Verify remote has the commit
  remote_log=$(git -C "$REMOTE_REPO" log --oneline -1)
  [[ "$remote_log" == *"sync: auto-update"* ]]
}

@test "sync reports push to remote(s)" {
  echo "data" > "$TEST_DOTFILES/data.conf"
  git -C "$TEST_DOTFILES" add data.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Synced and pushed"* ]]
  [[ "$output" == *"1 remote(s)"* ]]
}

# ── Pull remote changes ─────────────────────────────────────────

@test "sync pulls remote changes before committing" {
  # Push a commit from a second clone
  CLONE2="$TEST_DIR/clone2"
  git clone --quiet "$REMOTE_REPO" "$CLONE2"
  echo "remote change" > "$CLONE2/remote.conf"
  git -C "$CLONE2" add remote.conf
  git -C "$CLONE2" commit --no-verify -m "chore: remote update" --quiet
  git -C "$CLONE2" push --quiet

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]

  # The remote file should now exist locally
  [ -f "$TEST_DOTFILES/remote.conf" ]
}

# ── Edge cases ───────────────────────────────────────────────────

@test "sync handles not-a-git-repo gracefully" {
  NOT_GIT="$TEST_DIR/not-a-repo"
  mkdir -p "$NOT_GIT/bin" "$NOT_GIT/lib"
  cp "$SYNC_CMD" "$NOT_GIT/bin/dotfiles-sync"
  chmod +x "$NOT_GIT/bin/dotfiles-sync"
  cp "$BATS_TEST_DIRNAME/../lib/colors.sh" "$NOT_GIT/lib/colors.sh"
  cp "$BATS_TEST_DIRNAME/../lib/stats.sh" "$NOT_GIT/lib/stats.sh"
  cp "$BATS_TEST_DIRNAME/../lib/lock.sh" "$NOT_GIT/lib/lock.sh"
  cp "$BATS_TEST_DIRNAME/../lib/push-error-classify.sh" "$NOT_GIT/lib/push-error-classify.sh"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh" "$NOT_GIT/lib/agentbrew-locate.sh"

  run "$NOT_GIT/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Not a git repo"* ]]
}

@test "sync handles no remote gracefully" {
  NO_REMOTE="$TEST_DIR/no-remote"
  mkdir -p "$NO_REMOTE/bin" "$NO_REMOTE/lib"
  cp "$SYNC_CMD" "$NO_REMOTE/bin/dotfiles-sync"
  chmod +x "$NO_REMOTE/bin/dotfiles-sync"
  cp "$BATS_TEST_DIRNAME/../lib/colors.sh" "$NO_REMOTE/lib/colors.sh"
  cp "$BATS_TEST_DIRNAME/../lib/stats.sh" "$NO_REMOTE/lib/stats.sh"
  cp "$BATS_TEST_DIRNAME/../lib/lock.sh" "$NO_REMOTE/lib/lock.sh"
  cp "$BATS_TEST_DIRNAME/../lib/push-error-classify.sh" "$NO_REMOTE/lib/push-error-classify.sh"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-locate.sh" "$NO_REMOTE/lib/agentbrew-locate.sh"
  git -C "$NO_REMOTE" init --quiet
  git -C "$NO_REMOTE" add -A
  git -C "$NO_REMOTE" commit --no-verify --allow-empty -m "chore: init" --quiet

  run "$NO_REMOTE/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No remote configured"* ]]
}

@test "sync uses git add -u (only tracked files)" {
  grep -q 'git add -u' "$SYNC_CMD"
}

@test "sync recovers from stuck rebase" {
  grep -q 'rebase --abort' "$SYNC_CMD"
  grep -q 'rebase-merge\|rebase-apply' "$SYNC_CMD"
}

# ── Multiple remotes ─────────────────────────────────────────────

@test "sync pushes to all configured remotes" {
  # Add a second remote
  REMOTE2="$TEST_DIR/remote2.git"
  git init --bare --quiet "$REMOTE2"
  git -C "$TEST_DOTFILES" remote add backup "$REMOTE2"

  echo "multi" > "$TEST_DOTFILES/multi.conf"
  git -C "$TEST_DOTFILES" add multi.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 remote(s)"* ]]

  # Both remotes should have the commit
  remote1_log=$(git -C "$REMOTE_REPO" log --oneline -1)
  remote2_log=$(git -C "$REMOTE2" log --oneline -1)
  [[ "$remote1_log" == *"sync: auto-update"* ]]
  [[ "$remote2_log" == *"sync: auto-update"* ]]
}

# ── Stats logging ────────────────────────────────────────────────

@test "sync logs run to stats file on commit" {
  echo "stats-test" > "$TEST_DOTFILES/stats.conf"
  git -C "$TEST_DOTFILES" add stats.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [ -f "$DOTFILES_STATS_FILE" ]
  grep -q '"task":"sync"' "$DOTFILES_STATS_FILE"
}

# ── Deletion protection ──────────────────────────────────────────

@test "sync unstages file deletions instead of committing them" {
  # Create and track a file, then delete it from working tree
  echo "important" > "$TEST_DOTFILES/lib/helper.sh"
  git -C "$TEST_DOTFILES" add lib/helper.sh
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add helper" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null
  rm "$TEST_DOTFILES/lib/helper.sh"

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unstaged"* ]]
  [[ "$output" == *"deletion"* ]]

  # The deletion should NOT have been committed
  last_msg=$(git -C "$TEST_DOTFILES" log -1 --format='%s')
  [[ "$last_msg" != sync:\ auto-update* ]]
}

@test "sync commits modifications but skips deletions in same batch" {
  # Track an extra file, then modify one and delete another
  echo "keep" > "$TEST_DOTFILES/lib/keep.sh"
  echo "remove" > "$TEST_DOTFILES/lib/remove.sh"
  git -C "$TEST_DOTFILES" add lib/keep.sh lib/remove.sh
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add files" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null

  # Modify one, delete the other
  echo "modified" > "$TEST_DOTFILES/lib/keep.sh"
  rm "$TEST_DOTFILES/lib/remove.sh"

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Unstaged"* ]]
  [[ "$output" == *"Synced and pushed"* ]]

  # Modification should be committed, deletion should not
  git -C "$TEST_DOTFILES" show --stat HEAD | grep -q "keep.sh"
  ! git -C "$TEST_DOTFILES" show --stat HEAD | grep -q "remove.sh"
}

@test "sync reports no changes when only deletions are present" {
  echo "doomed" > "$TEST_DOTFILES/lib/doomed.sh"
  git -C "$TEST_DOTFILES" add lib/doomed.sh
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add doomed" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null
  rm "$TEST_DOTFILES/lib/doomed.sh"

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No changes after excluding deletions"* ]]
}

# ── Sync-protect ─────────────────────────────────────────────────

@test "sync skips files listed in .sync-protect" {
  # Create .sync-protect with a protected file
  cat > "$TEST_DOTFILES/.sync-protect" <<'PROTECT'
# Protected files
protected.conf
PROTECT
  git -C "$TEST_DOTFILES" add .sync-protect
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add sync-protect" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null

  # Create and track protected file, then modify it
  echo "original" > "$TEST_DOTFILES/protected.conf"
  git -C "$TEST_DOTFILES" add protected.conf
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add protected" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null
  echo "modified" > "$TEST_DOTFILES/protected.conf"

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped protected file"* ]]
  [[ "$output" == *"protected.conf"* ]]

  # Protected file should NOT have been committed
  last_msg=$(git -C "$TEST_DOTFILES" log -1 --format='%s')
  [[ "$last_msg" != sync:\ auto-update* ]]
}

@test "sync commits unprotected files while skipping protected ones" {
  cat > "$TEST_DOTFILES/.sync-protect" <<'PROTECT'
protected.conf
PROTECT
  echo "original" > "$TEST_DOTFILES/protected.conf"
  echo "original" > "$TEST_DOTFILES/unprotected.conf"
  git -C "$TEST_DOTFILES" add .sync-protect protected.conf unprotected.conf
  git -C "$TEST_DOTFILES" commit --no-verify -m "chore: add files" --quiet
  git -C "$TEST_DOTFILES" push --quiet 2>/dev/null

  # Modify both files
  echo "modified" > "$TEST_DOTFILES/protected.conf"
  echo "modified" > "$TEST_DOTFILES/unprotected.conf"

  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped protected file"* ]]
  [[ "$output" == *"Synced and pushed"* ]]

  # Only unprotected file should be in the commit
  local names_output
  names_output=$(git -C "$TEST_DOTFILES" diff --stat HEAD~1 HEAD --name-only)
  [[ "$names_output" == *"unprotected.conf"* ]]
  # Use word boundary: "protected.conf" alone (not part of "unprotected.conf")
  run bash -c "echo '$names_output' | grep -qx 'protected.conf'"
  [ "$status" -ne 0 ]
}

# ── Pipefail resilience ──────────────────────────────────────────

@test "sync survives when WebStorm is not installed" {
  # HOME is isolated (no WebStorm), script should not fail
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
}

# ── Dry-run mode ─────────────────────────────────────────────────

@test "sync runs chezmoi apply after successful pull" {
  grep -q 'chezmoi apply' "$SYNC_CMD"
}

@test "sync --dry-run with no changes reports no changes" {
  run "$TEST_DOTFILES/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"No changes"* ]]
}

@test "sync --dry-run with changes shows what would be committed without committing" {
  echo "preview" > "$TEST_DOTFILES/preview.conf"
  git -C "$TEST_DOTFILES" add preview.conf

  run "$TEST_DOTFILES/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"Would commit"* ]]
  [[ "$output" == *"preview.conf"* ]]
  [[ "$output" == *"Would push to"* ]]

  # Verify nothing was actually committed
  [ -n "$(git -C "$TEST_DOTFILES" status --porcelain)" ]
}

@test "sync --dry-run with untracked-only changes reports they are ignored" {
  echo "scratch" > "$TEST_DOTFILES/scratch.conf"

  run "$TEST_DOTFILES/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [[ "$output" == *"No tracked or staged changes to auto-commit"* ]]
  [[ "$output" == *"Ignoring 1 untracked file(s)"* ]]
  [[ "$output" == *"stage them explicitly to include"* ]]
  [[ "$output" != *"Would commit these"* ]]
}

# ── Performance regression tests ────────────────────────────────────

@test "sync completes in under 5 seconds on clean repo" {
  SECONDS=0
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  elapsed=$SECONDS
  [ "$elapsed" -lt 5 ]
}

# ── Push error classification ──────────────────────────────────────
# Replaces the legacy "(offline?)" catch-all so the LaunchAgent log is
# actually useful when something goes wrong. Each test sources the helper
# fresh so they stay independent of the main sync script's state.

_load_classifier() {
  # shellcheck disable=SC1090
  source "$BATS_TEST_DIRNAME/../lib/push-error-classify.sh"
}

@test "classifier: empty stderr → 'no stderr captured'" {
  _load_classifier
  run _classify_push_error ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"no stderr captured"* ]]
}

@test "classifier: protected-branch (GH006) message is recognized" {
  _load_classifier
  run _classify_push_error "remote: error: GH006: Protected branch update failed for refs/heads/main."
  [[ "$output" == *"branch protection"* ]]
}

@test "classifier: required-status-check failure is recognized" {
  _load_classifier
  run _classify_push_error "remote: required status check 'Ticket Check' is expected"
  [[ "$output" == *"branch protection"* ]]
}

@test "classifier: non-fast-forward (rejected) is recognized" {
  _load_classifier
  run _classify_push_error " ! [rejected]        feat/chezmoi -> feat/chezmoi (non-fast-forward)"
  [[ "$output" == *"non-fast-forward"* ]]
}

@test "classifier: DNS / offline error is recognized" {
  _load_classifier
  run _classify_push_error "ssh: Could not resolve hostname github.com: nodename nor servname provided"
  [[ "$output" == *"offline or DNS failure"* ]]
}

@test "classifier: auth failure is recognized" {
  _load_classifier
  run _classify_push_error "remote: Permission denied to alice."
  [[ "$output" == *"auth"* ]]
}

@test "classifier: pre-receive hook decline is recognized" {
  _load_classifier
  run _classify_push_error "remote: pre-receive hook declined"
  [[ "$output" == *"pre-receive"* ]]
}

@test "classifier: unknown error returns trimmed first non-blank line" {
  _load_classifier
  run _classify_push_error $'\n\nremote: server caught fire\nremote: more details here'
  [[ "$output" == *"server caught fire"* ]]
}

@test "sync never emits the legacy '(offline?)' fallback" {
  # Guards against regression — this string used to appear for every push
  # error regardless of cause and made the LaunchAgent log misleading.
  ! grep -q '(offline?)' "$SYNC_CMD"
}

# ── Multi-agent branch-gate (auto-sync-pollutes-checked-out-feature-branch) ──

@test "sync skips auto-commit/push on a non-canonical (feature) branch" {
  git -C "$TEST_DOTFILES" checkout -q -b chore/concurrent-agent-work
  local before; before=$(git -C "$TEST_DOTFILES" rev-list --count HEAD)
  # A concurrent session's staged work in the shared tree (would be swept
  # into a sync: auto-update commit on this branch without the gate)
  echo "concurrent work" > "$TEST_DOTFILES/concurrent.conf"
  git -C "$TEST_DOTFILES" add concurrent.conf
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  # No new commit landed on the feature branch
  [ "$before" -eq "$(git -C "$TEST_DOTFILES" rev-list --count HEAD)" ]
  # The work is left for the branch owner (still present, uncommitted)
  [ -n "$(git -C "$TEST_DOTFILES" status --porcelain concurrent.conf)" ]
  [[ "$output" == *"Skipping auto-sync"* ]]
}

@test "sync dry-run reports it would skip on a feature branch" {
  git -C "$TEST_DOTFILES" checkout -q -b fix/another-agent
  run "$TEST_DOTFILES/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would skip auto-sync"* ]]
}

@test "sync still auto-commits on the canonical branch (gate does not over-skip)" {
  # Repo starts on the canonical branch (origin/HEAD set in setup_file).
  local before; before=$(git -C "$TEST_DOTFILES" rev-list --count HEAD)
  echo "trunk work" > "$TEST_DOTFILES/trunk.conf"
  git -C "$TEST_DOTFILES" add trunk.conf
  run "$TEST_DOTFILES/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_DOTFILES" rev-list --count HEAD)" -eq "$((before + 1))" ]
  [[ "$(git -C "$TEST_DOTFILES" log --oneline -1)" == *"sync: auto-update"* ]]
}

# ── Linked worktrees and the applied checkout ───────────────────────

# Add a linked worktree on its own branch that tracks the canonical branch,
# plus a fake chezmoi whose source-path is $1 (default: the worktree) and
# that records apply calls. Like chezmoi v2, the fake rejects apply flags it
# does not know. Set FAKE_CHEZMOI_APPLY_ERROR to make apply fail.
setup_applied_worktree() {
  local canon
  canon="$(git -C "$TEST_DOTFILES" branch --show-current)"
  APPLIED="$TEST_DIR/applied"
  git -C "$TEST_DOTFILES" worktree add --quiet -b "applied/$canon" "$APPLIED" "origin/$canon"
  git -C "$APPLIED" branch --quiet --set-upstream-to="origin/$canon"
  local source_dir="${1:-$APPLIED}"
  mkdir -p "$TEST_DIR/fakebin"
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
case "\$1" in
  source-path) printf '%s\n' "$source_dir" ;;
  apply)
    args="\$*"
    shift
    while [ \$# -gt 0 ]; do
      case "\$1" in
        --source) shift ;;
        --force|--no-tty|--verbose|--dry-run) ;;
        -*) echo "chezmoi: unknown flag: \$1" >&2; exit 1 ;;
      esac
      shift
    done
    if [ -n "\${FAKE_CHEZMOI_APPLY_ERROR:-}" ]; then
      echo "chezmoi: \$FAKE_CHEZMOI_APPLY_ERROR" >&2
      exit 1
    fi
    printf '%s\n' "\$args" >> "$TEST_DIR/chezmoi-apply.log"
    ;;
esac
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  export PATH="$TEST_DIR/fakebin:$PATH"
}

# Push one commit to the remote from a second clone; print the new remote HEAD.
push_remote_commit() {
  local clone="$TEST_DIR/clone2"
  git clone --quiet "$REMOTE_REPO" "$clone"
  echo "remote change" > "$clone/remote.conf"
  git -C "$clone" add remote.conf
  git -C "$clone" commit --no-verify -m "chore: remote update" --quiet
  git -C "$clone" push --quiet
  git -C "$REMOTE_REPO" rev-parse HEAD
}

@test "sync runs in a linked worktree (.git is a file)" {
  git -C "$TEST_DOTFILES" worktree add --quiet -b chore/worktree-agent "$TEST_DIR/wt"
  [ -f "$TEST_DIR/wt/.git" ]
  run "$TEST_DIR/wt/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Not a git repo"* ]]
  [[ "$output" == *"Skipping auto-sync"* ]]
}

@test "sync fast-forwards the applied checkout and re-applies chezmoi" {
  setup_applied_worktree
  local remote_head; remote_head="$(push_remote_commit)"
  run "$APPLIED/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applied checkout at"*"chezmoi re-applied"* ]]
  [[ "$output" != *"chezmoi apply failed"* ]]
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$remote_head" ]
  grep -q -- "--source $APPLIED" "$TEST_DIR/chezmoi-apply.log"
  # Nothing was committed or pushed from the applied checkout
  [ "$(git -C "$REMOTE_REPO" rev-parse HEAD)" = "$remote_head" ]
  grep -q '"task":"sync"' "$DOTFILES_STATS_FILE"
}

@test "sync reports chezmoi's error when the applied re-apply fails" {
  setup_applied_worktree
  push_remote_commit >/dev/null
  FAKE_CHEZMOI_APPLY_ERROR="could not open a new TTY" run "$APPLIED/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"chezmoi apply failed: chezmoi: could not open a new TTY"* ]]
  [[ "$output" != *"chezmoi re-applied"* ]]
}

@test "sync output still reaches the log after the log is trimmed" {
  local log="$HOME/.local/share/dotfiles/logs/dotfiles-sync.log"
  mkdir -p "$(dirname "$log")"
  seq -f 'old line %g' 1 600 > "$log"
  git -C "$TEST_DOTFILES" worktree add --quiet -b chore/log-agent "$TEST_DIR/wt"
  # launchd opens the log once, in append mode, before the script starts.
  bash -c '"$1" >> "$2" 2>&1' _ "$TEST_DIR/wt/bin/dotfiles-sync" "$log"
  [ "$(head -n 1 "$log")" = "old line 101" ]
  grep -q 'Skipping auto-sync' "$log"
}

@test "sync leaves a dirty applied checkout untouched" {
  setup_applied_worktree
  local before; before="$(git -C "$APPLIED" rev-parse HEAD)"
  local remote_head; remote_head="$(push_remote_commit)"
  printf '\n# stray edit\n' >> "$APPLIED/lib/colors.sh"
  run "$APPLIED/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"uncommitted changes"* ]]
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$REMOTE_REPO" rev-parse HEAD)" = "$remote_head" ]
  [ -n "$(git -C "$APPLIED" status --porcelain lib/colors.sh)" ]
  [ ! -f "$TEST_DIR/chezmoi-apply.log" ]
}

@test "sync leaves a diverged applied checkout untouched" {
  setup_applied_worktree
  echo "local only" > "$APPLIED/local.conf"
  git -C "$APPLIED" add local.conf
  git -C "$APPLIED" commit --no-verify -m "chore: local only" --quiet
  local before; before="$(git -C "$APPLIED" rev-parse HEAD)"
  local remote_head; remote_head="$(push_remote_commit)"
  run "$APPLIED/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"diverged"* ]]
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$REMOTE_REPO" rev-parse HEAD)" = "$remote_head" ]
}

@test "sync still skips a feature worktree that tracks the canonical branch" {
  mkdir -p "$TEST_DIR/elsewhere"
  setup_applied_worktree "$TEST_DIR/elsewhere"
  local before; before="$(git -C "$APPLIED" rev-parse HEAD)"
  push_remote_commit >/dev/null
  run "$APPLIED/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping auto-sync"* ]]
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$before" ]
}

@test "sync dry-run reports the applied fast-forward without changing anything" {
  setup_applied_worktree
  local before; before="$(git -C "$APPLIED" rev-parse HEAD)"
  push_remote_commit >/dev/null
  run "$APPLIED/bin/dotfiles-sync" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Applied checkout: would fast-forward"* ]]
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$before" ]
  [ ! -f "$TEST_DIR/chezmoi-apply.log" ]
}

#!/usr/bin/env bats
# Tests for morning startup script

load test_helper
# These tests check stats writes, so they turn the stats log back on.
export DOTFILES_STATS_LOG=1

MORNING_CMD="$BATS_TEST_DIRNAME/../bin/morning"

setup() {
  TEST_DIR="$(mktemp -d)"
  # The tests expect "main". A clean machine has no init.defaultBranch.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=main
  TEST_HOME="$TEST_DIR/home"
  TEST_REPOS="$TEST_DIR/repos"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$TEST_HOME" "$TEST_REPOS" "$STUB_DIR"
  export HOME="$TEST_HOME"
  export DOTFILES_REPOS_DIR="$TEST_REPOS"
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"

  # Git config for test repos
  git config --global user.email "test@test.com"
  git config --global user.name "Test"

  # Stub softwareupdate — no real macOS update check in tests
  cat > "$STUB_DIR/softwareupdate" << 'STUB'
#!/bin/bash
echo "Software Update Tool"
echo "No new software available."
STUB
  chmod +x "$STUB_DIR/softwareupdate"

  # Stub perl — replace alarm-wrapped calls with direct exec
  cat > "$STUB_DIR/perl" << 'STUB'
#!/bin/bash
# Strip the alarm wrapper: perl -e 'alarm 30; exec @ARGV' <cmd> <args>
shift  # -e
shift  # 'alarm ...; exec @ARGV'
exec "$@"
STUB
  chmod +x "$STUB_DIR/perl"

  # Stub df — report 50GB free (healthy)
  cat > "$STUB_DIR/df" << 'STUB'
#!/bin/bash
echo "Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on"
echo "/dev/disk1 976000000 500000000 50 5% 1000 999000 0% /"
STUB
  chmod +x "$STUB_DIR/df"

  # Stub dotfiles-doctor
  cat > "$STUB_DIR/dotfiles-doctor" << 'STUB'
#!/bin/bash
echo "All checks passed"
echo "21 modules, 130 checks"
echo "0 failures"
STUB
  chmod +x "$STUB_DIR/dotfiles-doctor"

  # Stub ps — avoid real process listing in tests
  cat > "$STUB_DIR/ps" << 'STUB'
#!/bin/bash
echo "  PID  %CPU %MEM COMMAND"
echo "  123  1.0  2.0 /usr/bin/test-process"
STUB
  chmod +x "$STUB_DIR/ps"

  # Put stubs first in PATH (but keep real git, etc.)
  export PATH="$STUB_DIR:$PATH"

  # Source stats for log_run / get_time_saved_summary
  # shellcheck source=../lib/stats.sh
  source "$BATS_TEST_DIRNAME/../lib/stats.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: create a git repo on main branch with a remote
create_test_repo() {
  local name="$1"
  local bare="$TEST_DIR/bare-${name}.git"
  local repo="$TEST_REPOS/$name"
  git init --bare --quiet "$bare"
  git init --quiet "$repo"
  echo "content" > "$repo/README.md"
  git -C "$repo" add -A
  git -C "$repo" commit --no-verify -m "initial" --quiet
  git -C "$repo" branch -M main
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push --quiet -u origin main 2>/dev/null
}

# ── Content-based checks (existing) ──────────────────────────────

@test "morning script exists and is executable" {
  [ -f "$MORNING_CMD" ]
  [ -x "$MORNING_CMD" ]
}

@test "morning script has correct shebang" {
  head -1 "$MORNING_CMD" | grep -q '#!/bin/bash'
}

@test "morning script sources stats.sh" {
  grep -q 'source.*lib/stats.sh' "$MORNING_CMD"
}

@test "morning script uses DOTFILES_REPOS_DIR with fallback" {
  grep -q 'DOTFILES_REPOS_DIR:-' "$MORNING_CMD"
}

@test "morning script only pulls repos on main or master branch" {
  # Verify the branch filter logic exists in the script
  grep -q 'branch.*main.*master' "$MORNING_CMD"
  # Verify it skips non-main branches
  grep -q 'continue' "$MORNING_CMD"
  # Verify it allows only a fast-forward, even with a configured rebase.
  grep -q 'git pull --ff-only --no-rebase' "$MORNING_CMD"
}

@test "morning script runs doctor" {
  grep -q 'dotfiles-doctor' "$MORNING_CMD"
}

@test "morning script checks disk space" {
  grep -q 'df -g' "$MORNING_CMD"
}

@test "morning script checks for macOS updates" {
  grep -q 'softwareupdate' "$MORNING_CMD"
}

@test "morning script logs run with repos_pulled count" {
  grep -q 'log_run morning' "$MORNING_CMD"
}

@test "morning script shows top resource usage" {
  grep -q 'Top resource usage' "$MORNING_CMD"
}

@test "morning script shows time saved summary" {
  grep -q 'get_time_saved_summary' "$MORNING_CMD"
}

@test "morning script shows today's notes from ~/.notes/" {
  grep -q '\.notes/' "$MORNING_CMD"
  grep -q 'your first note' "$MORNING_CMD"
}

# ── Functional tests ─────────────────────────────────────────────

@test "morning pulls repos on main branch" {
  create_test_repo "alpha"

  # Push a new commit to the remote (simulate upstream change)
  local clone="$TEST_DIR/clone-alpha"
  git clone --quiet "$TEST_DIR/bare-alpha.git" "$clone"
  echo "upstream change" > "$clone/UPSTREAM.md"
  git -C "$clone" add -A
  git -C "$clone" commit --no-verify -m "upstream" --quiet
  git -C "$clone" push --quiet 2>/dev/null

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  # The repo should now have the upstream file
  [ -f "$TEST_REPOS/alpha/UPSTREAM.md" ]
  [ "$(git -C "$TEST_REPOS/alpha" rev-parse HEAD)" = "$(git -C "$clone" rev-parse HEAD)" ]
}

@test "morning leaves the local branch on its original root after an upstream rewrite" {
  create_test_repo "rewritten"
  local repo="$TEST_REPOS/rewritten" replacement="$TEST_DIR/replacement" old_head new_head
  old_head="$(git -C "$repo" rev-parse HEAD)"
  git init --bare --quiet "$TEST_DIR/replacement.git"
  git init --quiet "$replacement"
  printf 'new upstream root\n' > "$replacement/NEW.md"
  git -C "$replacement" add NEW.md
  git -C "$replacement" commit --quiet -m "new root"
  git -C "$replacement" push --quiet "$TEST_DIR/replacement.git" main
  new_head="$(git -C "$replacement" rev-parse HEAD)"
  git -C "$repo" remote set-url origin "$TEST_DIR/replacement.git"
  git -C "$repo" fetch --quiet
  ! git -C "$repo" merge-base "$old_head" "$new_head"
  git -C "$repo" config pull.rebase true

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  if [ "$(git -C "$repo" rev-parse HEAD)" != "$old_head" ]; then
    echo "Expected the original local HEAD after an upstream rewrite" >&2
    return 1
  fi
  [ -z "$(git -C "$repo" status --porcelain)" ]
  [ "$(cat "$repo/README.md")" = content ]
  [ ! -e "$repo/NEW.md" ]
  [[ "$output" == *"rewritten: refresh skipped"* ]]
  [[ "$output" == *"status --short --branch"* ]]
}

@test "morning leaves a diverged local branch unchanged" {
  create_test_repo "diverged"
  local repo="$TEST_REPOS/diverged" upstream="$TEST_DIR/upstream" old_head
  git clone --quiet "$TEST_DIR/bare-diverged.git" "$upstream"
  printf 'incoming change\n' > "$upstream/UPSTREAM.md"
  git -C "$upstream" add UPSTREAM.md
  git -C "$upstream" commit --quiet -m "upstream work"
  git -C "$upstream" push --quiet
  printf 'local edit\n' > "$repo/LOCAL.md"
  git -C "$repo" add LOCAL.md
  git -C "$repo" commit --quiet -m "local work"
  old_head="$(git -C "$repo" rev-parse HEAD)"

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  if [ "$(git -C "$repo" rev-parse HEAD)" != "$old_head" ]; then
    echo "Expected the original local HEAD after branch divergence" >&2
    return 1
  fi
  [ -z "$(git -C "$repo" status --porcelain)" ]
  [ "$(cat "$repo/LOCAL.md")" = 'local edit' ]
  [ ! -e "$repo/UPSTREAM.md" ]
  [[ "$output" == *"diverged: refresh skipped"* ]]
}

@test "morning skips repos on non-main branches" {
  create_test_repo "beta"
  git -C "$TEST_REPOS/beta" checkout -b feature-branch --quiet

  # Push a new commit to remote main
  local clone="$TEST_DIR/clone-beta"
  git clone --quiet "$TEST_DIR/bare-beta.git" "$clone"
  echo "upstream" > "$clone/UPSTREAM.md"
  git -C "$clone" add -A
  git -C "$clone" commit --no-verify -m "upstream" --quiet
  git -C "$clone" push --quiet 2>/dev/null

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  # The repo is on feature-branch, so it should NOT have the upstream file
  [ ! -f "$TEST_REPOS/beta/UPSTREAM.md" ]
}

@test "morning skips directories without .git" {
  mkdir -p "$TEST_REPOS/not-a-repo"
  echo "just a folder" > "$TEST_REPOS/not-a-repo/README.md"

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  # No crash — script handles non-git dirs gracefully
  [[ "$output" != *"fatal"* ]]
}

@test "morning shows disk space check" {
  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Disk:"* ]] || [[ "$output" == *"Low disk"* ]]
}

@test "morning shows macOS update status" {
  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]] || [[ "$output" == *"update"* ]]
}

@test "morning shows today's notes when file exists" {
  mkdir -p "$HOME/.notes"
  echo "Remember to review PRs" > "$HOME/.notes/$(date +%Y-%m-%d).md"

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Remember to review PRs"* ]]
}

@test "morning shows no-notes hint when no notes exist" {
  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No notes yet today"* ]]
}

@test "morning logs run to stats file" {
  create_test_repo "gamma"

  run bash "$MORNING_CMD"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/stats.jsonl" ]
  grep -q '"morning"' "$TEST_DIR/stats.jsonl"
}

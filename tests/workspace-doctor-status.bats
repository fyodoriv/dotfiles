#!/usr/bin/env bats
# Tests for bin/dotfiles-workspace status + modules/workspace/doctor.sh.
# Fixture: two workspaces — one with a git repo (1 dirty line, 1 commit,
# no upstream) and a TASKS.md repo (2 unchecked tasks, 1 of them blocked).
# See docs/plans/workspace-folder-doctor.md.

BIN="$BATS_TEST_DIRNAME/../bin/dotfiles-workspace"
MODULE="$BATS_TEST_DIRNAME/../modules/workspace/doctor.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  SCAN_ROOT="$TEST_DIR/apps"
  mkdir -p "$TEST_HOME"

  # Workspace 1: "tooling" with one git repo (dirty) and one plain dir.
  REPO="$SCAN_ROOT/tooling/repo-git"
  mkdir -p "$REPO" "$SCAN_ROOT/tooling/plain-dir"
  touch "$SCAN_ROOT/tooling/.tasks-md-workspace"
  ( cd "$REPO" && \
    git -c init.defaultBranch=main init -q && \
    git config core.hooksPath /dev/null && \
    git config core.excludesFile /dev/null && \
    git config user.email "t@x.com" && git config user.name "t" && \
    echo seed > seed.txt && git add -- seed.txt && \
    git commit -q --no-verify -m "init" && \
    echo dirty > dirty.txt )

  # Workspace 2: "work" qualifies via two child TASKS.md files.
  mkdir -p "$SCAN_ROOT/work/repo-a" "$SCAN_ROOT/work/repo-b"
  printf '%s\n' "# Tasks" "" "## P1" "" \
    "- [ ] First task" \
    "  - **ID**: t-one" \
    "- [ ] Second task" \
    "  - **ID**: t-two" \
    "  - **Blocked**: needs-user-approval — example" \
    > "$SCAN_ROOT/work/repo-a/TASKS.md"
  printf '%s\n' "# Tasks" "" "## P2" "" \
    "- [ ] Third task" \
    "  - **ID**: t-three" \
    > "$SCAN_ROOT/work/repo-b/TASKS.md"

  export HOME="$TEST_HOME"
  export WORKSPACE_SCAN_ROOTS="$SCAN_ROOT"
}

teardown() { rm -rf "$TEST_DIR"; }

# ── Structural ─────────────────────────────────────────────────────

@test "workspace bin: exists, executable, --help exits 0" {
  [ -x "$BIN" ]
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"status"* ]]
}

@test "workspace module: exists, executable, no hardcoded /Users paths" {
  [ -x "$MODULE" ]
  ! grep -q '"/Users/' "$MODULE"
}

@test "workspace module: registers at least 4 workspace checks" {
  local count
  count=$(grep -cE 'check[[:space:]]+"workspace\.|check_advisory[[:space:]]+"workspace\.' "$MODULE")
  [ "$count" -ge 4 ]
}

# ── Functional: status ─────────────────────────────────────────────

@test "workspace status: two-workspace fixture reports correct summaries" {
  run "$BIN" status
  [ "$status" -eq 0 ]
  # Workspace headers
  [[ "$output" == *"=== Workspace: work ($SCAN_ROOT/work) ==="* ]]
  [[ "$output" == *"=== Workspace: tooling ($SCAN_ROOT/tooling) ==="* ]]
  # Git repo line: 1 dirty line, no upstream marker
  [[ "$output" == *"✓ repo-git"* ]]
  [[ "$output" == *"1 dirty"* ]]
  # TASKS.md counts: repo-a has 2 unchecked / 1 blocked → 1 unblocked;
  # repo-b has 1 unchecked / 0 blocked → 1 unblocked.
  [[ "$output" == *"repo-a: 2 tasks (1 unblocked)"* ]]
  [[ "$output" == *"repo-b: 1 tasks (1 unblocked)"* ]]
  # Per-workspace totals
  [[ "$output" == *"Total: 1 repos, 0 tasks"* ]]      # tooling
  [[ "$output" == *"Total: 0 repos, 3 tasks"* ]]      # work
  # Cross-workspace rollup
  [[ "$output" == *"=== All workspaces: 2 workspaces, 1 repos, 3 tasks ==="* ]]
}

@test "workspace status: --workspace scopes to one" {
  run "$BIN" status --workspace work
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== Workspace: work"* ]]
  [[ "$output" != *"=== Workspace: tooling"* ]]
}

@test "workspace status: unknown --workspace exits 2 and lists names" {
  run "$BIN" status --workspace nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"work"* ]]
  [[ "$output" == *"tooling"* ]]
}

@test "workspace status: no workspaces found exits 0 with a note" {
  EMPTY_ROOT="$TEST_DIR/empty"
  mkdir -p "$EMPTY_ROOT"
  WORKSPACE_SCAN_ROOTS="$EMPTY_ROOT" run "$BIN" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"no workspaces"* ]]
}

@test "workspace status: rejects unknown flags" {
  run "$BIN" status --bogus
  [ "$status" -ne 0 ]
}

@test "workspace status: broken checkout is flagged, not fatal" {
  # A dir with a .git that isn't a valid work tree (bare/worktree-container,
  # e.g. an orchestrator-managed checkout) must produce a ✗ line and the
  # rollup must still complete with rc 0 — one broken repo can't kill the
  # host-level view.
  mkdir -p "$SCAN_ROOT/tooling/broken-repo/.git"
  run "$BIN" status --workspace tooling
  [ "$status" -eq 0 ]
  [[ "$output" == *"✗ broken-repo"* ]]
  [[ "$output" == *"✓ repo-git"* ]]
  [[ "$output" == *"=== All workspaces: 1 workspaces, 2 repos"* ]]
}

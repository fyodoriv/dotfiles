#!/usr/bin/env bats
# bin/agent-scratch-prune removes only safe agent scratch: idle build output,
# clean pushed idle worktrees, and old mktemp/goal scratch folders. These
# tests pin what it must keep: recent work, dirty or unpushed worktrees,
# locked worktrees, evidence files, and anything outside its roots.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/agent-scratch-prune"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  STATE="$HOME/.local/state"
  WT_ROOT="$HOME/.codex/worktrees"
  mkdir -p "$STATE" "$WT_ROOT"
  TMPD="$TEST_DIR/T"
  mkdir -p "$TMPD"
  # Never let a test reach the real per-user temp folder.
  export AGENT_SCRATCH_STATE_DIR="$STATE" AGENT_SCRATCH_WORKTREE_ROOTS="$WT_ROOT" AGENT_SCRATCH_TMP_DIR="$TMPD"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# age PATH DAYS — set every entry under PATH to DAYS days old.
age() {
  local stamp
  stamp="$(date -v-"$2"d +%Y%m%d%H%M)"
  find "$1" -exec touch -h -t "$stamp" {} + 2>/dev/null
}

# A repo with a bare remote, and a worktree at $WT_ROOT/<name>/repo.
make_worktree() {
  local name="$1"
  git init -q --bare "$TEST_DIR/remote.git" 2>/dev/null || true
  if [ ! -d "$TEST_DIR/main" ]; then
    git init -q -b main "$TEST_DIR/main"
    echo a > "$TEST_DIR/main/f"
    git -C "$TEST_DIR/main" add f
    git -C "$TEST_DIR/main" commit -qm init
    git -C "$TEST_DIR/main" remote add origin "$TEST_DIR/remote.git"
    git -C "$TEST_DIR/main" push -q origin main
  fi
  mkdir -p "$WT_ROOT/$name"
  git -C "$TEST_DIR/main" worktree add -q --detach "$WT_ROOT/$name/repo" origin/main
}

@test "removes idle node_modules, .venv and Cargo target, keeps the project files" {
  mkdir -p "$STATE/goal.Ab3xYz/proj/node_modules/x" "$STATE/goal.Ab3xYz/proj/.venv" "$STATE/goal.Ab3xYz/proj/out-target"
  touch "$STATE/goal.Ab3xYz/proj/.venv/pyvenv.cfg" "$STATE/goal.Ab3xYz/proj/out-target/CACHEDIR.TAG" "$STATE/goal.Ab3xYz/proj/out-target/.rustc_info.json"
  echo evidence > "$STATE/goal.Ab3xYz/proj/receipt.md"
  age "$STATE/goal.Ab3xYz" 3
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/goal.Ab3xYz/proj/node_modules" ]
  [ ! -e "$STATE/goal.Ab3xYz/proj/.venv" ]
  [ ! -e "$STATE/goal.Ab3xYz/proj/out-target" ]
  [ -f "$STATE/goal.Ab3xYz/proj/receipt.md" ]
}

@test "keeps build output when the project changed recently" {
  mkdir -p "$STATE/run.Ab3xYz/proj/node_modules/x"
  age "$STATE/run.Ab3xYz" 3
  echo new > "$STATE/run.Ab3xYz/proj/today.txt"
  run "$SCRIPT"
  [ -d "$STATE/run.Ab3xYz/proj/node_modules" ]
}

@test "keeps a .venv without pyvenv.cfg and a target without CACHEDIR.TAG" {
  mkdir -p "$STATE/run.Ab3xYz/proj/.venv" "$STATE/run.Ab3xYz/proj/target"
  echo x > "$STATE/run.Ab3xYz/proj/notes.md"
  age "$STATE/run.Ab3xYz" 3
  run "$SCRIPT"
  [ -d "$STATE/run.Ab3xYz/proj/.venv" ]
  [ -d "$STATE/run.Ab3xYz/proj/target" ]
}

@test "keeps a CACHEDIR.TAG folder that is not a Cargo target" {
  mkdir -p "$STATE/run.Ab3xYz/tool-state/data"
  touch "$STATE/run.Ab3xYz/tool-state/CACHEDIR.TAG"
  echo x > "$STATE/run.Ab3xYz/tool-state/data/db"
  echo x > "$STATE/run.Ab3xYz/notes.md"
  age "$STATE/run.Ab3xYz" 3
  run "$SCRIPT"
  [ -f "$STATE/run.Ab3xYz/tool-state/data/db" ]
}

@test "keeps build output that is being written now" {
  mkdir -p "$STATE/run.Ab3xYz/proj/node_modules/x"
  echo x > "$STATE/run.Ab3xYz/proj/package.json"
  age "$STATE/run.Ab3xYz" 3
  echo x > "$STATE/run.Ab3xYz/proj/node_modules/x/index.js"
  run "$SCRIPT"
  [ -f "$STATE/run.Ab3xYz/proj/node_modules/x/index.js" ]
}

@test "--dry-run removes nothing and reports the total" {
  mkdir -p "$STATE/run.Ab3xYz/proj/node_modules/x"
  age "$STATE/run.Ab3xYz" 40
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would free"* ]]
  [ -d "$STATE/run.Ab3xYz/proj/node_modules" ]
}

@test "deletes a mktemp scratch folder idle past the limit, keeps a younger one" {
  mkdir -p "$STATE/careerbrew-old.Ab3xYz9q" "$STATE/careerbrew-new.Qw7erTy1"
  echo x > "$STATE/careerbrew-old.Ab3xYz9q/log"
  echo x > "$STATE/careerbrew-new.Qw7erTy1/log"
  age "$STATE/careerbrew-old.Ab3xYz9q" 31
  age "$STATE/careerbrew-new.Qw7erTy1" 10
  run "$SCRIPT"
  [ ! -e "$STATE/careerbrew-old.Ab3xYz9q" ]
  [ -d "$STATE/careerbrew-new.Qw7erTy1" ]
}

@test "never deletes non-scratch state folders, however old" {
  mkdir -p "$STATE/agentbrew" "$STATE/tooling-cutover" "$STATE/notes.backup"
  echo x > "$STATE/agentbrew/keep"
  age "$STATE" 400
  run "$SCRIPT"
  [ -f "$STATE/agentbrew/keep" ]
  [ -d "$STATE/tooling-cutover" ]
  [ -d "$STATE/notes.backup" ]
}

@test "goal folders lose only entries idle past the limit" {
  mkdir -p "$STATE/tooling-goal-2026-09-01/old-run" "$STATE/tooling-goal-2026-09-01/new-run"
  echo x > "$STATE/tooling-goal-2026-09-01/old.patch"
  echo x > "$STATE/tooling-goal-2026-09-01/old-run/log"
  echo x > "$STATE/tooling-goal-2026-09-01/new-run/log"
  age "$STATE/tooling-goal-2026-09-01" 45
  touch "$STATE/tooling-goal-2026-09-01/new-run/log"
  run "$SCRIPT"
  [ ! -e "$STATE/tooling-goal-2026-09-01/old-run" ]
  [ ! -e "$STATE/tooling-goal-2026-09-01/old.patch" ]
  [ -f "$STATE/tooling-goal-2026-09-01/new-run/log" ]
}

@test "AGENT_SCRATCH_DIR_IDLE_DAYS changes the folder limit" {
  mkdir -p "$STATE/run.Ab3xYz9q"
  echo x > "$STATE/run.Ab3xYz9q/log"
  age "$STATE/run.Ab3xYz9q" 31
  AGENT_SCRATCH_DIR_IDLE_DAYS=60 run "$SCRIPT"
  [ -d "$STATE/run.Ab3xYz9q" ]
}

@test "removes a clean, pushed, idle worktree through git" {
  make_worktree done
  age "$WT_ROOT/done" 10
  age "$TEST_DIR/main/.git/worktrees" 10
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$WT_ROOT/done" ]
  run git -C "$TEST_DIR/main" worktree list
  [[ "$output" != *"done"* ]]
}

@test "keeps a worktree with uncommitted changes" {
  make_worktree dirty
  echo change >> "$WT_ROOT/dirty/repo/f"
  age "$WT_ROOT/dirty" 10
  age "$TEST_DIR/main/.git/worktrees" 10
  run "$SCRIPT"
  [ -f "$WT_ROOT/dirty/repo/f" ]
}

@test "keeps a worktree with a commit no remote has" {
  make_worktree ahead
  echo b > "$WT_ROOT/ahead/repo/g"
  git -C "$WT_ROOT/ahead/repo" add g
  git -C "$WT_ROOT/ahead/repo" commit -qm local
  age "$WT_ROOT/ahead" 10
  age "$TEST_DIR/main/.git/worktrees" 10
  run "$SCRIPT"
  [ -f "$WT_ROOT/ahead/repo/g" ]
}

@test "keeps a locked worktree and a recently used one" {
  make_worktree locked
  make_worktree recent
  git -C "$TEST_DIR/main" worktree lock "$WT_ROOT/locked/repo"
  age "$WT_ROOT/locked" 10
  age "$TEST_DIR/main/.git/worktrees/locked" 10 2>/dev/null || age "$TEST_DIR/main/.git/worktrees" 10
  run "$SCRIPT"
  [ -d "$WT_ROOT/locked/repo" ]
  [ -d "$WT_ROOT/recent/repo" ]
}

@test "removes an empty, idle worktree shell folder" {
  mkdir -p "$WT_ROOT/shell/empty"
  age "$WT_ROOT/shell" 10
  run "$SCRIPT"
  [ ! -e "$WT_ROOT/shell" ]
}

@test "follows no symlink out of its roots" {
  mkdir -p "$TEST_DIR/outside/proj/node_modules/x"
  age "$TEST_DIR/outside" 40
  ln -s "$TEST_DIR/outside" "$STATE/link.Ab3xYz9q"
  run "$SCRIPT"
  [ -d "$TEST_DIR/outside/proj/node_modules" ]
}

@test "rejects an unknown option" {
  run "$SCRIPT" --force
  [ "$status" -eq 2 ]
}

@test "removes temp entries idle 3 days, keeps recent and app entries" {
  mkdir -p "$TMPD/careerbrew-web.Ab3xYz/node_modules" "$TMPD/fresh.Qw7erT" "$TMPD/com.docker.abc"
  echo x > "$TMPD/careerbrew-web.Ab3xYz/node_modules/a.js"
  echo x > "$TMPD/fresh.Qw7erT/log"
  echo x > "$TMPD/com.docker.abc/state"
  echo x > "$TMPD/old-file.txt"
  age "$TMPD" 4
  touch "$TMPD/fresh.Qw7erT/log"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$TMPD/careerbrew-web.Ab3xYz" ]
  [ ! -e "$TMPD/old-file.txt" ]
  [ -f "$TMPD/fresh.Qw7erT/log" ]
  [ -f "$TMPD/com.docker.abc/state" ]
}

@test "keeps a temp entry that one file inside still uses" {
  mkdir -p "$TMPD/run.Ab3xYz/deep/er"
  echo x > "$TMPD/run.Ab3xYz/old"
  age "$TMPD" 10
  echo x > "$TMPD/run.Ab3xYz/deep/er/new"
  run "$SCRIPT"
  [ -f "$TMPD/run.Ab3xYz/old" ]
}

@test "trims its log in place, so launchd keeps writing to the same file" {
  log="$HOME/.local/share/dotfiles/logs/agent-scratch-prune.log"
  mkdir -p "$(dirname "$log")"
  seq 1 3000 > "$log"
  before="$(stat -f %i "$log")"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stat -f %i "$log")" = "$before" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 2000 ]
}

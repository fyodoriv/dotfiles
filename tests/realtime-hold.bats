#!/usr/bin/env bats
# lib/realtime-hold.sh: periodic jobs (dotfiles-sync, tooling-sync,
# agent-scratch-prune) skip one run while a real-time app (a game stream)
# runs, the same list heavy-run holds for. A stub pgrep stands in for the app.

load test_helper

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/pgrep" <<'EOF'
#!/bin/bash
# Stub: FakeGame runs; BrokenProbe fails; everything else is absent.
case "$2" in
  FakeGame) echo 4242; exit 0 ;;
  BrokenProbe) exit 3 ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/pgrep"
  export PATH="$TEST_DIR/bin:$PATH"
  export DOTFILES_REALTIME_HOLD=1
  export HEAVY_RUN_PAUSE_APPS="Other,FakeGame"
}

teardown() {
  rm -rf "$TEST_DIR"
}

hold() { bash -c 'source "$1/lib/realtime-hold.sh"; realtime_app_running' _ "$REPO"; }

@test "realtime_app_running prints the first running app" {
  run hold
  [ "$status" -eq 0 ]
  [ "$output" = "FakeGame" ]
}

@test "realtime_app_running returns 1 when no listed app runs" {
  HEAVY_RUN_PAUSE_APPS="Other" run hold
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "an empty app list turns the hold off" {
  HEAVY_RUN_PAUSE_APPS="" run hold
  [ "$status" -eq 1 ]
}

@test "DOTFILES_REALTIME_HOLD=0 turns the hold off" {
  DOTFILES_REALTIME_HOLD=0 run hold
  [ "$status" -eq 1 ]
}

@test "a failed probe counts as not running" {
  HEAVY_RUN_PAUSE_APPS="BrokenProbe" run hold
  [ "$status" -eq 1 ]
}

@test "the default list is GeForceNOW, shared with heavy-run" {
  grep -q 'HEAVY_RUN_PAUSE_APPS-GeForceNOW' "$REPO/lib/realtime-hold.sh"
  grep -q 'HEAVY_RUN_PAUSE_APPS-GeForceNOW' "$REPO/bin/heavy-run"
}

@test "dotfiles-sync skips before any Git work while a real-time app runs" {
  cat > "$TEST_DIR/bin/git" <<EOF
#!/bin/bash
touch "$TEST_DIR/git-ran"; exit 99
EOF
  chmod +x "$TEST_DIR/bin/git"
  run "$REPO/bin/dotfiles-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped: FakeGame is running"* ]]
  [ ! -e "$TEST_DIR/git-ran" ]
}

@test "tooling-sync skips and leaves the hourly slot unclaimed" {
  export XDG_DATA_HOME="$TEST_DIR/xdg"
  run "$REPO/bin/tooling-sync"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped: FakeGame is running"* ]]
  [ ! -f "$XDG_DATA_HOME/tooling-sync/last-run" ]
}

@test "agent-scratch-prune skips and removes nothing" {
  export AGENT_SCRATCH_STATE_DIR="$HOME/.local/state" AGENT_SCRATCH_WORKTREE_ROOTS="$TEST_DIR/wt" AGENT_SCRATCH_TMP_DIR="$TEST_DIR/T"
  mkdir -p "$TEST_DIR/T/goal-old" "$TEST_DIR/wt"
  touch -t 202001010000 "$TEST_DIR/T/goal-old" "$TEST_DIR/T"
  run "$REPO/bin/agent-scratch-prune"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped: FakeGame is running"* ]]
  [ -d "$TEST_DIR/T/goal-old" ]
}

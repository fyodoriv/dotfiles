#!/usr/bin/env bats
# Tests for home/zshrc.tasks — GitHub Issues task CLI aliases

load test_helper

ZSHRC_TASKS="$BATS_TEST_DIRNAME/../home/zshrc.tasks"

setup() {
  # Create a mock tasks command that captures invocations
  TEST_DIR="$(mktemp -d)"
  MOCK_TASKS="$TEST_DIR/tasks"
  TASKS_ARGS="$TEST_DIR/tasks-args.txt"
  
  cat > "$MOCK_TASKS" <<'STUB'
#!/bin/bash
# Mock tasks CLI that captures arguments
printf '%s\n' "$@" > "$TASKS_ARGS"
exit 0
STUB
  chmod +x "$MOCK_TASKS"
  
  export TASKS_ARGS
  export PATH="$TEST_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "zshrc.tasks file exists and is readable" {
  [ -f "$ZSHRC_TASKS" ]
  [ -r "$ZSHRC_TASKS" ]
}

@test "zshrc.tasks defines task-next function" {
  grep -q 'task-next()' "$ZSHRC_TASKS"
}

@test "zshrc.tasks defines task-list function" {
  grep -q 'task-list()' "$ZSHRC_TASKS"
}

@test "zshrc.tasks defines task-new function" {
  grep -q 'task-new()' "$ZSHRC_TASKS"
}

@test "zshrc.tasks defines task-done function" {
  grep -q 'task-done()' "$ZSHRC_TASKS"
}

@test "zshrc.tasks defines task-mine function" {
  grep -q 'task-mine()' "$ZSHRC_TASKS"
}

@test "task-next invokes tasks pick" {
  # Source the file and run task-next
  source "$ZSHRC_TASKS"
  
  # Mock tasks command
  tasks() { printf '%s\n' "$@" > "$TASKS_ARGS"; }
  export -f tasks
  
  task-next
  
  [ -f "$TASKS_ARGS" ]
  grep -q 'pick' "$TASKS_ARGS"
}

@test "task-list invokes tasks list with arguments" {
  source "$ZSHRC_TASKS"
  
  tasks() { printf '%s\n' "$@" > "$TASKS_ARGS"; }
  export -f tasks
  
  task-list --json
  
  [ -f "$TASKS_ARGS" ]
  grep -q 'list' "$TASKS_ARGS"
  grep -q '\--json' "$TASKS_ARGS"
}

@test "task-new invokes tasks create with arguments" {
  source "$ZSHRC_TASKS"
  
  tasks() { printf '%s\n' "$@" > "$TASKS_ARGS"; }
  export -f tasks
  
  task-new "Test task" --priority P1
  
  [ -f "$TASKS_ARGS" ]
  grep -q 'create' "$TASKS_ARGS"
  grep -q 'Test task' "$TASKS_ARGS"
  grep -q 'P1' "$TASKS_ARGS"
}

@test "task-done invokes tasks complete with arguments" {
  source "$ZSHRC_TASKS"
  
  tasks() { printf '%s\n' "$@" > "$TASKS_ARGS"; }
  export -f tasks
  
  task-done 123
  
  [ -f "$TASKS_ARGS" ]
  grep -q 'complete' "$TASKS_ARGS"
  grep -q '123' "$TASKS_ARGS"
}

@test "task-mine invokes tasks list with --json" {
  source "$ZSHRC_TASKS"
  
  tasks() { printf '%s\n' "$@" > "$TASKS_ARGS"; }
  export -f tasks
  
  task-mine
  
  [ -f "$TASKS_ARGS" ]
  grep -q 'list' "$TASKS_ARGS"
  grep -q '\--json' "$TASKS_ARGS"
}

@test "functions resolve tasks via command -v or npx fallback" {
  # Verify the functions use the resolution pattern
  grep -q 'command -v tasks' "$ZSHRC_TASKS" || grep -q 'npx.*@tasks-md/cli' "$ZSHRC_TASKS"
}

@test "zshrc.tasks respects existing bin/gh wrapper" {
  # Verify that the file doesn't bypass the gh wrapper
  # (it should use tasks CLI, not gh directly)
  ! grep -q 'command gh' "$ZSHRC_TASKS" || grep -q 'bin/gh' "$ZSHRC_TASKS"
}

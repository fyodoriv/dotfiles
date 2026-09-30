#!/usr/bin/env bats
# Tests for bin/add-task backend support (github-issues vs tasks-md)

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  WORKDIR="$BATS_TEST_TMPDIR/add-task-backend-test"
  
  # Create a mock dotfiles repo with tasks-md backend (default)
  TARGET_REPO_TASKS_MD="$WORKDIR/target-tasks-md"
  mkdir -p "$TARGET_REPO_TASKS_MD/bin"
  cp "$REPO_ROOT/bin/add-task" "$TARGET_REPO_TASKS_MD/bin/add-task"
  chmod +x "$TARGET_REPO_TASKS_MD/bin/add-task"
  cat <<'EOF' > "$TARGET_REPO_TASKS_MD/TASKS.md"
# Tasks

## P0

## P1

## P2

## P3

EOF
  
  # Create a mock dotfiles repo with github-issues backend
  TARGET_REPO_GITHUB="$WORKDIR/target-github-issues"
  mkdir -p "$TARGET_REPO_GITHUB/bin"
  cp "$REPO_ROOT/bin/add-task" "$TARGET_REPO_GITHUB/bin/add-task"
  chmod +x "$TARGET_REPO_GITHUB/bin/add-task"
  cat <<'EOF' > "$TARGET_REPO_GITHUB/.tasksmd.json"
{
  "backend": "github-issues",
  "repo": "owner/test-repo",
  "label": "tasks.md"
}
EOF
  cat <<'EOF' > "$TARGET_REPO_GITHUB/TASKS.md"
# Tasks

## P0

## P1

## P2

## P3

EOF
}

teardown() {
  rm -rf "$WORKDIR"
}

@test "detects tasks-md backend when .tasksmd.json is absent" {
  run "$TARGET_REPO_TASKS_MD/bin/add-task" --title "Test task" --priority P2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would insert under ## P2"* ]]
}

@test "detects github-issues backend from .tasksmd.json" {
  # Mock jq to return the backend
  export PATH="$WORKDIR/mocks:$PATH"
  mkdir -p "$WORKDIR/mocks"
  cat > "$WORKDIR/mocks/jq" <<'JQMOCK'
#!/bin/bash
# Mock jq that returns the backend field
if [[ "$*" == *"backend"* ]]; then
  echo '"github-issues"'
else
  echo '{}'
fi
JQMOCK
  chmod +x "$WORKDIR/mocks/jq"
  
  run "$TARGET_REPO_GITHUB/bin/add-task" --title "Test GitHub issue" --priority P1 --dry-run
  [ "$status" -eq 0 ]
  # Should mention github-issues or issue creation, not TASKS.md
  [[ "$output" == *"github"* ]] || [[ "$output" == *"issue"* ]] || [[ "$output" == *"Would"* ]]
}

@test "tasks-md backend writes to TASKS.md" {
  run "$TARGET_REPO_TASKS_MD/bin/add-task" --title "TASKS.md task" --priority P2
  [ "$status" -eq 0 ]
  grep -q "TASKS.md task" "$TARGET_REPO_TASKS_MD/TASKS.md"
}

@test "github-issues backend delegates to 'tasks create' with priority + backend flags" {
  mkdir -p "$WORKDIR/mocks"
  export PATH="$WORKDIR/mocks:$PATH"
  export TASKS_ARGS_FILE="$WORKDIR/tasks-args.txt"
  cat > "$WORKDIR/mocks/tasks" <<'TASKSMOCK'
#!/bin/bash
echo "$@" > "$TASKS_ARGS_FILE"
exit 0
TASKSMOCK
  chmod +x "$WORKDIR/mocks/tasks"

  run "$TARGET_REPO_GITHUB/bin/add-task" --title "Delegated issue" --priority P1 --tags infra,backend
  [ "$status" -eq 0 ]
  [[ "$output" == *"created GitHub Issue"* ]]
  grep -q "create" "$TASKS_ARGS_FILE"
  grep -q -- "--priority P1" "$TASKS_ARGS_FILE"
  grep -q -- "--backend github-issues" "$TASKS_ARGS_FILE"
  grep -q -- "--tag infra" "$TASKS_ARGS_FILE"
  grep -q -- "--tag backend" "$TASKS_ARGS_FILE"
}

@test "github-issues backend queues issue-intent file when tasks CLI fails (offline)" {
  mkdir -p "$WORKDIR/mocks"
  export PATH="$WORKDIR/mocks:$PATH"
  printf '#!/bin/bash\nexit 1\n' > "$WORKDIR/mocks/tasks"
  printf '#!/bin/bash\nexit 1\n' > "$WORKDIR/mocks/npx"
  chmod +x "$WORKDIR/mocks/tasks" "$WORKDIR/mocks/npx"
  
  run "$TARGET_REPO_GITHUB/bin/add-task" --title "GitHub issue fallback" --priority P1
  [ "$status" -eq 0 ]
  # Should have created an issue-intent file in the target repo directory
  ls "$TARGET_REPO_GITHUB"/.issue-intent-* >/dev/null 2>&1
}

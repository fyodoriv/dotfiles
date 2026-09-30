#!/usr/bin/env bats
# Tests for bin/add-task — the helper that appends properly-formatted
# TASKS.md entries from the command line.

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  WORKDIR="$BATS_TEST_TMPDIR/add-task-test"
  mkdir -p "$WORKDIR/bin"
  cp "$REPO_ROOT/bin/add-task" "$WORKDIR/bin/add-task"
  chmod +x "$WORKDIR/bin/add-task"
  cat <<'EOF' > "$WORKDIR/TASKS.md"
# Tasks

## P0

## P1

- [ ] Existing P1 task
  - **ID**: existing-p1
  - **Tags**: existing

## P2

## P3

EOF
}

@test "--help prints usage" {
  cd "$WORKDIR"
  run bin/add-task --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "missing --title is rejected when stdin is not a tty" {
  cd "$WORKDIR"
  run bash -c "echo '' | bin/add-task"
  [ "$status" -eq 2 ]
}

@test "invalid --priority is rejected" {
  cd "$WORKDIR"
  run bin/add-task --title "x" --priority P9
  [ "$status" -eq 2 ]
  [[ "$output" == *"P0 / P1 / P2 / P3"* ]]
}

@test "duplicate ID is rejected" {
  cd "$WORKDIR"
  run bin/add-task --title "Different title" --priority P1 --id existing-p1
  [ "$status" -eq 2 ]
  [[ "$output" == *"already exists"* ]]
}

@test "auto-derives ID from title via slugification" {
  cd "$WORKDIR"
  run bin/add-task --title "Hello World, Part 2!" --priority P2 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-world-part-2"* ]]
}

@test "dry-run does not modify TASKS.md" {
  cd "$WORKDIR"
  cp TASKS.md TASKS.md.before
  bin/add-task --title "Dry test" --priority P3 --dry-run >/dev/null
  diff TASKS.md TASKS.md.before
}

@test "P1 task without rule-9 fields is rejected" {
  cd "$WORKDIR"
  run bin/add-task --title "Needs hypothesis" --priority P1 --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"P1 tasks require --hypothesis, --success, --pivot, --measurement, and --anchor"* ]]
}

@test "writes entry under the chosen priority section" {
  cd "$WORKDIR"
  run bin/add-task --title "New P3 task" --priority P3 --tags foo,bar
  [ "$status" -eq 0 ]
  # The new entry should appear after the `## P3` header.
  awk '/^## P3/{flag=1; next} flag' TASKS.md | grep -q "New P3 task"
}

@test "writes only the optional fields that are non-empty" {
  cd "$WORKDIR"
  run bin/add-task --title "Minimal task" --priority P2
  [ "$status" -eq 0 ]
  # Should have ID but NOT Tags, Details, Files, Acceptance lines.
  run grep -c "minimal-task" TASKS.md
  [ "$output" = "1" ]
  # Check that the inserted entry has ID but no Tags/Details/etc.
  awk '/Minimal task/{found=1; next} found && /^- \[ \]/{exit} found' TASKS.md > /tmp/entry-body.$$
  grep -q '\*\*ID\*\*: minimal-task' /tmp/entry-body.$$
  ! grep -q '\*\*Tags\*\*:' /tmp/entry-body.$$
  ! grep -q '\*\*Details\*\*:' /tmp/entry-body.$$
  rm /tmp/entry-body.$$
}

@test "writes optional fields when provided" {
  cd "$WORKDIR"
  run bin/add-task --title "Full task" --priority P2 --tags a,b --details "Some details" --files "x.sh" --acceptance "It works"
  [ "$status" -eq 0 ]
  awk '/Full task/{found=1; next} found && /^- \[ \]/{exit} found' TASKS.md > /tmp/entry-body.$$
  grep -q '\*\*Tags\*\*: a,b' /tmp/entry-body.$$
  grep -q '\*\*Details\*\*: Some details' /tmp/entry-body.$$
  grep -q '\*\*Files\*\*: x.sh' /tmp/entry-body.$$
  grep -q '\*\*Acceptance\*\*: It works' /tmp/entry-body.$$
  rm /tmp/entry-body.$$
}

@test "writes P1 rule-9 fields when provided" {
  cd "$WORKDIR"
  run bin/add-task --title "Rule 9 task" --priority P1 --tags a,b \
    --hypothesis "h" --success "s" --pivot "p" --measurement "m" --anchor "a" \
    --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"**Hypothesis**: h"* ]]
  [[ "$output" == *"**Success**: s"* ]]
  [[ "$output" == *"**Pivot**: p"* ]]
  [[ "$output" == *"**Measurement**: m"* ]]
  [[ "$output" == *"**Anchor**: a"* ]]
}

@test "output mentions next-steps git commands" {
  cd "$WORKDIR"
  run bin/add-task --title "Output test" --priority P3
  [ "$status" -eq 0 ]
  [[ "$output" == *"git add TASKS.md"* ]]
  [[ "$output" == *"git commit"* ]]
  [[ "$output" == *"open a PR"* ]]
}

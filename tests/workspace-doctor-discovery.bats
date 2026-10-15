#!/usr/bin/env bats
# Tests for lib/workspace-discovery.sh — workspace_discover resolution
# order: tasks-md workspaces.json → workspaces.yaml → sentinel/structure
# scan of $WORKSPACE_SCAN_ROOTS. See docs/plans/workspace-folder-doctor.md.

LIB="$BATS_TEST_DIRNAME/../lib/workspace-discovery.sh"

# Run workspace_discover with an isolated HOME + scan roots.
_discover() {
  local home="$1" roots="$2"
  HOME="$home" WORKSPACE_SCAN_ROOTS="$roots" bash -c \
    "source '$LIB' && workspace_discover"
}

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  SCAN_ROOT="$TEST_DIR/apps"
  mkdir -p "$TEST_HOME" "$SCAN_ROOT"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "discovery: lib exists and is sourceable" {
  [ -f "$LIB" ]
  run bash -c "source '$LIB' && type workspace_discover"
  [ "$status" -eq 0 ]
}

@test "discovery: N=0 — empty scan root yields no output, rc 0" {
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "discovery: N=1 — sentinel file marks a workspace" {
  mkdir -p "$SCAN_ROOT/tooling"
  touch "$SCAN_ROOT/tooling/.tasks-md-workspace"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == "tooling	$SCAN_ROOT/tooling" ]]
}

@test "discovery: N=2 — sentinel + two-TASKS.md structure heuristic" {
  mkdir -p "$SCAN_ROOT/tooling"
  touch "$SCAN_ROOT/tooling/.tasks-md-workspace"
  mkdir -p "$SCAN_ROOT/work/repo-a" "$SCAN_ROOT/work/repo-b"
  echo "# Tasks" > "$SCAN_ROOT/work/repo-a/TASKS.md"
  echo "# Tasks" > "$SCAN_ROOT/work/repo-b/TASKS.md"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"work	$SCAN_ROOT/work"* ]]
  [[ "$output" == *"tooling	$SCAN_ROOT/tooling"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = "2" ]
}

@test "discovery: a dir with only ONE child TASKS.md is not a workspace" {
  mkdir -p "$SCAN_ROOT/single/repo-a"
  echo "# Tasks" > "$SCAN_ROOT/single/repo-a/TASKS.md"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "discovery: workspaces.json declared paths win over scanning" {
  # Config declares one workspace; the scan root contains a sentinel dir
  # that must NOT appear when the config exists.
  mkdir -p "$TEST_HOME/.config/tasks-md" "$TEST_DIR/declared"
  printf '{"declared": "%s"}\n' "$TEST_DIR/declared" \
    > "$TEST_HOME/.config/tasks-md/workspaces.json"
  mkdir -p "$SCAN_ROOT/scanned"
  touch "$SCAN_ROOT/scanned/.tasks-md-workspace"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == "declared	$TEST_DIR/declared" ]]
}

@test "discovery: workspaces.json array shape is accepted" {
  mkdir -p "$TEST_HOME/.config/tasks-md" "$TEST_DIR/ws-a"
  printf '[{"name": "alpha", "path": "%s"}]\n' "$TEST_DIR/ws-a" \
    > "$TEST_HOME/.config/tasks-md/workspaces.json"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == "alpha	$TEST_DIR/ws-a" ]]
}

@test "discovery: workspaces.yaml name: path lines are accepted" {
  mkdir -p "$TEST_HOME/.config/tasks-md" "$TEST_DIR/ws-y"
  printf '# comment\ntooling: %s\n' "$TEST_DIR/ws-y" \
    > "$TEST_HOME/.config/tasks-md/workspaces.yaml"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == "tooling	$TEST_DIR/ws-y" ]]
}

@test "discovery: multi-root WORKSPACE_SCAN_ROOTS (colon-separated)" {
  ROOT2="$TEST_DIR/work"
  mkdir -p "$SCAN_ROOT/alpha" "$ROOT2/beta"
  touch "$SCAN_ROOT/alpha/.tasks-md-workspace"
  touch "$ROOT2/beta/.tasks-md-workspace"
  run _discover "$TEST_HOME" "$SCAN_ROOT:$ROOT2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha	$SCAN_ROOT/alpha"* ]]
  [[ "$output" == *"beta	$ROOT2/beta"* ]]
}

@test "discovery: tilde in config path expands to HOME" {
  mkdir -p "$TEST_HOME/.config/tasks-md" "$TEST_HOME/myws"
  printf '{"home-ws": "~/myws"}\n' \
    > "$TEST_HOME/.config/tasks-md/workspaces.json"
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == "home-ws	$TEST_HOME/myws" ]]
}

# ── tasks-md spec shape (spec.md § Workspaces) ──────────────────────
# `tasks workspaces add` writes {"workspaces":[{"name","root",...}],
# "discovery":{...}} to $XDG_CONFIG_HOME/tasks-md/workspaces.json.

@test "discovery: tasks-md spec shape (workspaces[].root) is read, discovery block ignored" {
  mkdir -p "$TEST_HOME/.config/tasks-md" "$TEST_DIR/tooling" "$TEST_HOME/work"
  cat > "$TEST_HOME/.config/tasks-md/workspaces.json" <<JSON
{
  "workspaces": [
    { "name": "tooling", "root": "$TEST_DIR/tooling", "exclude": ["archived-repo"], "priorityWeight": 1.0 },
    { "name": "work", "root": "~/work" }
  ],
  "discovery": { "scanRoots": ["~/apps"], "autoDetect": true }
}
JSON
  run _discover "$TEST_HOME" "$SCAN_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "tooling	$TEST_DIR/tooling
work	$TEST_HOME/work" ]
}

@test "discovery: XDG_CONFIG_HOME config wins, like the tasks CLI" {
  mkdir -p "$TEST_DIR/xdg/tasks-md" "$TEST_DIR/xdg-ws"
  printf '{"workspaces":[{"name":"xdg","root":"%s"}]}\n' "$TEST_DIR/xdg-ws" \
    > "$TEST_DIR/xdg/tasks-md/workspaces.json"
  run env XDG_CONFIG_HOME="$TEST_DIR/xdg" HOME="$TEST_HOME" WORKSPACE_SCAN_ROOTS="$SCAN_ROOT" \
    bash -c "source '$LIB' && workspace_discover"
  [ "$status" -eq 0 ]
  [ "$output" = "xdg	$TEST_DIR/xdg-ws" ]
}

@test "discovery: reads a config written by the real 'tasks workspaces add'" {
  command -v tasks >/dev/null 2>&1 || skip "tasks CLI (tasks-md) not installed"
  mkdir -p "$TEST_HOME/apps/stack/repo-a" "$TEST_DIR/xdg"
  echo "# Tasks" > "$TEST_HOME/apps/stack/repo-a/TASKS.md"
  HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_DIR/xdg" \
    tasks workspaces add "$TEST_HOME/apps/stack" --name stack >/dev/null
  # The writer stores HOME-relative roots as "~/...".
  grep -q '"root": "~/apps/stack"' "$TEST_DIR/xdg/tasks-md/workspaces.json"
  run env XDG_CONFIG_HOME="$TEST_DIR/xdg" HOME="$TEST_HOME" WORKSPACE_SCAN_ROOTS="$SCAN_ROOT" \
    bash -c "source '$LIB' && workspace_discover"
  [ "$status" -eq 0 ]
  [ "$output" = "stack	$TEST_HOME/apps/stack" ]
}

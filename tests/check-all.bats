#!/usr/bin/env bats
# Tests for check-all — cached lint/test across ~/apps repos

CHECK_ALL="$BATS_TEST_DIRNAME/../bin/check-all"

setup() {
  TEST_DIR="$(mktemp -d)"
  export APPS_DIR="$TEST_DIR/apps"
  mkdir -p "$APPS_DIR"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "check-all exists and is executable" {
  [ -x "$CHECK_ALL" ]
}

@test "check-all has correct shebang" {
  head -1 "$CHECK_ALL" | grep -q '#!/bin/bash'
}

@test "check-all uses strict mode" {
  grep -q 'set -euo pipefail' "$CHECK_ALL"
}

@test "--help shows usage and exits 0" {
  run bash "$CHECK_ALL" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: check-all"* ]]
}

@test "-h shows usage and exits 0" {
  run bash "$CHECK_ALL" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: check-all"* ]]
}

@test "exits 1 when APPS_DIR does not exist" {
  export APPS_DIR="/nonexistent/path"
  run bash "$CHECK_ALL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"APPS_DIR not found"* ]]
}

@test "exits 0 with empty apps directory" {
  run bash "$CHECK_ALL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Passed: 0"* ]]
}

@test "detects Makefile check target" {
  mkdir -p "$APPS_DIR/myrepo/.git"
  cat > "$APPS_DIR/myrepo/Makefile" <<'EOF'
check:
	echo "ok"
EOF
  # Force mode so it doesn't need cached-run
  run bash "$CHECK_ALL" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"myrepo"* ]]
  [[ "$output" == *"Passed: 1"* ]]
}

@test "detects npm test in package.json" {
  mkdir -p "$APPS_DIR/jsrepo/.git"
  cat > "$APPS_DIR/jsrepo/package.json" <<'EOF'
{"scripts":{"test":"echo ok"}}
EOF
  run bash "$CHECK_ALL" --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"jsrepo"* ]]
}

@test "skips repos without check/test targets" {
  mkdir -p "$APPS_DIR/empty-repo/.git"
  run bash "$CHECK_ALL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Passed: 0"* ]]
}

@test "warns for nonexistent named repo" {
  run bash "$CHECK_ALL" nonexistent
  [ "$status" -eq 0 ]
  [[ "$output" == *"not found"* ]]
}

@test "reports failed repos" {
  mkdir -p "$APPS_DIR/bad-repo/.git"
  cat > "$APPS_DIR/bad-repo/Makefile" <<'EOF'
check:
	exit 1
EOF
  run bash "$CHECK_ALL" --force
  [ "$status" -eq 1 ]
  [[ "$output" == *"Failed: 1"* ]]
  [[ "$output" == *"bad-repo"* ]]
}

@test "detects yarn verify when yarn.lock exists" {
  mkdir -p "$APPS_DIR/yarnrepo/.git"
  cat > "$APPS_DIR/yarnrepo/package.json" <<'EOF'
{"scripts":{"verify":"echo ok"}}
EOF
  touch "$APPS_DIR/yarnrepo/yarn.lock"
  # We can test detection by checking the output includes the repo
  run bash "$CHECK_ALL" --force
  [[ "$output" == *"yarnrepo"* ]]
}

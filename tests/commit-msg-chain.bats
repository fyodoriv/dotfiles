#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/source/git-hooks" "$TEST_DIR/source/lib" "$TEST_DIR/overlay/hooks" "$TEST_DIR/repo/hooks"
  cp "$BATS_TEST_DIRNAME/../git-hooks/commit-msg" "$TEST_DIR/source/git-hooks/commit-msg"
  cp "$BATS_TEST_DIRNAME/../lib/strip-agent-attribution.sh" "$TEST_DIR/source/lib/"
  cat > "$TEST_DIR/source/lib/oss-readiness.sh" <<'SH'
oss_readiness_run_overlay_hook() {
  local hook="$TEST_OVERLAY/hooks/$1"
  shift
  [ -x "$hook" ] || return 0
  "$hook" "$@"
}
SH
  export TEST_OVERLAY="$TEST_DIR/overlay"
  export XDG_CONFIG_HOME="$TEST_DIR/config"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset MINSKY_PIPELINE
  git init --quiet "$TEST_DIR/repo"
  git -C "$TEST_DIR/repo" config user.name Fixture
  git -C "$TEST_DIR/repo" config user.email fixture@example.com
  git -C "$TEST_DIR/repo" config core.hooksPath "$TEST_DIR/source/git-hooks"
  printf fixture > "$TEST_DIR/repo/tracked"
  git -C "$TEST_DIR/repo" add tracked
}

teardown() { rm -rf "$TEST_DIR"; }

@test "overlay commit-msg edit persists in a real commit" {
  cat > "$TEST_OVERLAY/hooks/commit-msg" <<'SH'
#!/bin/bash
printf '\nOverlay-note: fixture\n' >> "$1"
SH
  chmod +x "$TEST_OVERLAY/hooks/commit-msg"
  run git -C "$TEST_DIR/repo" commit --quiet -m 'feat: fixture change'
  [ "$status" -eq 0 ]
  run git -C "$TEST_DIR/repo" log -1 --format=%B
  [[ "$output" == *'Overlay-note: fixture'* ]]
  [ "$(printf '%s\n' "$output" | grep -c 'Overlay-note: fixture')" -eq 1 ]
}

@test "overlay failure stops the commit before the repo hook" {
  cat > "$TEST_OVERLAY/hooks/commit-msg" <<'SH'
#!/bin/bash
echo 'overlay rejected fixture' >&2
exit 43
SH
  cat > "$TEST_DIR/repo/hooks/commit-msg" <<'SH'
#!/bin/bash
echo 'repo hook must not run' >&2
SH
  chmod +x "$TEST_OVERLAY/hooks/commit-msg" "$TEST_DIR/repo/hooks/commit-msg"
  run git -C "$TEST_DIR/repo" commit --quiet -m 'feat: fixture change'
  [ "$status" -ne 0 ]
  [[ "$output" == *'overlay rejected fixture'* ]]
  [[ "$output" != *'repo hook must not run'* ]]
  run git -C "$TEST_DIR/repo" rev-parse --verify HEAD
  [ "$status" -ne 0 ]
}

@test "without an overlay hook the repo hook still receives the message" {
  cat > "$TEST_DIR/repo/hooks/commit-msg" <<'SH'
#!/bin/bash
printf '\nRepo-note: fixture\n' >> "$1"
SH
  chmod +x "$TEST_DIR/repo/hooks/commit-msg"
  run git -C "$TEST_DIR/repo" commit --quiet -m 'feat: fixture change'
  [ "$status" -eq 0 ]
  run git -C "$TEST_DIR/repo" log -1 --format=%B
  [[ "$output" == *'Repo-note: fixture'* ]]
}

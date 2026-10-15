#!/usr/bin/env bats
# Tests for the pre-commit TASKS.md lint gate and the endpoint Node marker.

load test_helper

HOOK="$BATS_TEST_DIRNAME/../git-hooks/pre-commit"

setup() {
  # A global core.hooksPath (set by dotfiles itself) would run the installed
  # hook instead of the copy under test.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=.git/hooks
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  unset DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  TEST_REPO="$TEST_DIR/repo"
  git init --quiet "$TEST_REPO"

  # The dotfiles-only gates fire when the repo has bin/dotfiles-doctor.
  mkdir -p "$TEST_REPO/bin"
  touch "$TEST_REPO/bin/dotfiles-doctor"
  echo "0.7.0" > "$TEST_REPO/.tasks-lint-version"
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit --no-verify -m "chore: initial" --quiet

  cp "$HOOK" "$TEST_REPO/.git/hooks/pre-commit"
  chmod +x "$TEST_REPO/.git/hooks/pre-commit"

  STUB_BIN="$TEST_DIR/stub-bin"
  mkdir -p "$STUB_BIN"
  # An official Node.js build carries the Node.js Foundation team ID.
  cat > "$STUB_BIN/node" <<'STUB'
#!/bin/bash
exit 0
STUB
  cat > "$STUB_BIN/codesign" <<'STUB'
#!/bin/bash
echo "TeamIdentifier=HX7739G8FX" >&2
STUB
  cat > "$STUB_BIN/npx" <<'STUB'
#!/bin/bash
target="${*: -1}"
if [ -f "$target" ] && [ "$(head -1 "$target")" = "# Tasks" ]; then
  exit 0
fi
echo "TASKS.md must start with # Tasks"
exit 1
STUB
  chmod +x "$STUB_BIN"/*
  export PATH="$STUB_BIN:$PATH"

  cd "$TEST_REPO"
  echo "not a task queue" > TASKS.md
  git add -f TASKS.md
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "pre-commit lints TASKS.md with official Node when the endpoint marker is absent" {
  run git commit -m "chore: malformed tasks"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TASKS.md lint failed"* ]]
  [[ "$output" != *"deferred to CI"* ]]
}

@test "pre-commit skips the TASKS.md lint and names the marker when the endpoint blocks Node" {
  mkdir -p "$HOME/.local/state/dotfiles"
  : > "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run git commit -m "chore: malformed tasks"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TASKS.md lint skipped"* ]]
  [[ "$output" == *"endpoint-node-publisher-blocked"* ]]
  [[ "$output" != *"deferred to CI"* ]]
}

@test "pre-commit lints TASKS.md despite the marker when the override is set" {
  mkdir -p "$HOME/.local/state/dotfiles"
  : > "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"
  run env DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1 git commit -m "chore: malformed tasks"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TASKS.md lint failed"* ]]
}

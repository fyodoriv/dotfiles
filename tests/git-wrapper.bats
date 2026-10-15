#!/usr/bin/env bats

load test_helper

GIT_WRAPPER="$BATS_TEST_DIRNAME/../bin/git"

setup() {
  TEST_DIR="$(mktemp -d)"
  GIT_STUB="$TEST_DIR/real-git"
  GIT_ARGS="$TEST_DIR/git-args.txt"
  cat > "$GIT_STUB" <<'STUB'
#!/bin/bash
case " $* " in
  *" remote get-url "*)
    printf '%s\n' "git@git.example.corp:tooling/dotfiles.git"
    ;;
  *)
    printf '%s\n' "$*" > "$GIT_ARGS"
    ;;
esac
exit 0
STUB
  chmod +x "$GIT_STUB"
  POLICY_GIT_STUB="$TEST_DIR/policy-git"
  cat > "$POLICY_GIT_STUB" <<'STUB'
#!/bin/bash
case " $* " in
  *" remote get-url "*)
    printf '%s\n' "${FAKE_REMOTE_URL:-}"
    ;;
  *)
    printf '%s\n' "$*" > "$GIT_ARGS"
    ;;
esac
exit 0
STUB
  chmod +x "$POLICY_GIT_STUB"
  export DOTFILES_REAL_GIT="$GIT_STUB"
  export POLICY_GIT_STUB
  export GIT_ARGS
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "agent git push --no-verify is blocked without current-session approval" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GIT_WRAPPER" push --no-verify origin feature

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored 'git push --no-verify'"* ]]
}

@test "agent git -C push --no-verify is also blocked" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GIT_WRAPPER" -C /tmp push --no-verify origin feature

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored 'git push --no-verify'"* ]]
}

@test "agent git push without --no-verify passes through" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GIT_WRAPPER" push origin feature

  [ "$status" -eq 0 ]
  grep -q "push origin feature" "$GIT_ARGS"
}

@test "agent git push to approved public mirror passes through" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    DOTFILES_REAL_GIT="$POLICY_GIT_STUB" \
    FAKE_REMOTE_URL="https://github.com/fyodoriv/agentbrew.git" \
    "$GIT_WRAPPER" -C /tmp push origin feature

  [ "$status" -eq 0 ]
  grep -q -- "-C /tmp push origin feature" "$GIT_ARGS"
}

@test "agent git push to approved public mirror URL passes through" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    DOTFILES_REAL_GIT="$POLICY_GIT_STUB" \
    "$GIT_WRAPPER" push "git@github.com:fyodoriv/dotfiles.git" feature

  [ "$status" -eq 0 ]
  grep -q -- "push git@github.com:fyodoriv/dotfiles.git feature" "$GIT_ARGS"
}

@test "agent git push to another public repository is blocked" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    DOTFILES_REAL_GIT="$POLICY_GIT_STUB" \
    FAKE_REMOTE_URL="https://github.com/fyodoriv/not-approved.git" \
    "$GIT_WRAPPER" -C /tmp push origin feature

  [ "$status" -eq 1 ]
  [[ "$output" == *"unapproved public repository"* ]]
}

@test "agent git push to enterprise remote passes through" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    DOTFILES_REAL_GIT="$POLICY_GIT_STUB" \
    FAKE_REMOTE_URL="git@git.example.corp:tooling/dotfiles.git" \
    "$GIT_WRAPPER" -C /tmp push origin feature

  [ "$status" -eq 0 ]
  grep -q -- "-C /tmp push origin feature" "$GIT_ARGS"
}

@test "agent git push --no-verify passes with exact approval marker" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_PUBLIC_WRITE_APPROVAL="command=git push --no-verify remote=origin ref=feature" \
    "$GIT_WRAPPER" push --no-verify origin feature

  [ "$status" -eq 0 ]
  grep -q "push --no-verify origin feature" "$GIT_ARGS"
}

@test "agent git push --no-verify approval must cover the ref" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 \
    AGENT_PUBLIC_WRITE_APPROVAL="command=git push --no-verify remote=origin ref=other-feature" \
    "$GIT_WRAPPER" push --no-verify origin feature

  [ "$status" -eq 1 ]
  [[ "$output" == *"blocked agent-authored 'git push --no-verify'"* ]]
  [[ "$output" == *"ref=feature"* ]]
}

# ── real-git resolution ─────────────────────────────────────────────────────
#
# An unaccepted Xcode licence leaves /usr/bin/git executable but failing on
# every call. The wrapper must probe each candidate and skip a broken one.
# DOTFILES_SYSTEM_GIT stands in for /usr/bin/git so the tests stay hermetic.

make_git_candidates() {
  BROKEN_SYSTEM_GIT="$TEST_DIR/system/git"
  HEALTHY_SYSTEM_GIT="$TEST_DIR/system-ok/git"
  PATH_GIT_DIR="$TEST_DIR/path-bin"
  mkdir -p "$TEST_DIR/system" "$TEST_DIR/system-ok" "$PATH_GIT_DIR"
  printf '#!/bin/bash\necho "Xcode license not accepted" >&2\nexit 69\n' > "$BROKEN_SYSTEM_GIT"
  printf '#!/bin/bash\necho "system-git $*"\n' > "$HEALTHY_SYSTEM_GIT"
  printf '#!/bin/bash\necho "path-git $*"\n' > "$PATH_GIT_DIR/git"
  chmod +x "$BROKEN_SYSTEM_GIT" "$HEALTHY_SYSTEM_GIT" "$PATH_GIT_DIR/git"
}

@test "real-git resolution skips an executable system git that fails to run" {
  make_git_candidates
  run env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$BROKEN_SYSTEM_GIT" \
    PATH="$PATH_GIT_DIR:/usr/bin:/bin" "$GIT_WRAPPER" --version

  [ "$status" -eq 0 ]
  [[ "$output" == "path-git --version" ]]
}

@test "real-git resolution keeps the system git when it is healthy" {
  make_git_candidates
  run env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$HEALTHY_SYSTEM_GIT" \
    PATH="$PATH_GIT_DIR:/usr/bin:/bin" "$GIT_WRAPPER" status

  [ "$status" -eq 0 ]
  [[ "$output" == "system-git status" ]]
}

@test "real-git resolution prefers DOTFILES_REAL_GIT when it is executable" {
  make_git_candidates
  run env DOTFILES_REAL_GIT="$PATH_GIT_DIR/git" \
    DOTFILES_SYSTEM_GIT="$HEALTHY_SYSTEM_GIT" "$GIT_WRAPPER" status

  [ "$status" -eq 0 ]
  [[ "$output" == "path-git status" ]]
}

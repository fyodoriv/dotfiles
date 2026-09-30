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

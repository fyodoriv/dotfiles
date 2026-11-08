#!/usr/bin/env bats

load test_helper

GIT_WRAPPER="$BATS_TEST_DIRNAME/../bin/git"

setup() {
  TEST_DIR="$(mktemp -d)"
  # Keep probe markers out of the real ~/.cache.
  export XDG_CACHE_HOME="$TEST_DIR/cache"
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

# Probe cache (#483): a passing probe leaves a marker; the marker must not
# outlive an Xcode or CLT update, which replaces the developer-dir git.

counting_system_git() {
  COUNT_FILE="$TEST_DIR/probe-count"
  mkdir -p "$TEST_DIR/sys"
  CACHED_SYSTEM_GIT="$TEST_DIR/sys/git"
  printf '#!/bin/bash\n[ "$1" = --version ] && echo x >> "%s"\necho "system-git $*"\n' "$COUNT_FILE" > "$CACHED_SYSTEM_GIT"
  chmod +x "$CACHED_SYSTEM_GIT"
  touch -t 202001010000 "$CACHED_SYSTEM_GIT"
  # Stands in for the Xcode or CLT usr/bin directory.
  DEV_GIT="$TEST_DIR/dev-bin"
  mkdir -p "$DEV_GIT"
  touch -t 202001010000 "$DEV_GIT"
}

@test "probe cache: a healthy system git is probed once, then skipped" {
  counting_system_git
  for _ in 1 2 3; do
    run env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" \
      DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="/usr/bin:/bin" "$GIT_WRAPPER" status
    [ "$status" -eq 0 ]
    [[ "$output" == "system-git status" ]]
  done
  [ "$(wc -l < "$COUNT_FILE" | tr -d ' ')" -eq 1 ]
}

@test "probe cache: an Xcode or CLT bin dir newer than the marker forces a new probe" {
  counting_system_git
  make_git_candidates
  run env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" \
    DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="$PATH_GIT_DIR:/usr/bin:/bin" "$GIT_WRAPPER" status
  [[ "$output" == "system-git status" ]]
  # Simulate an Xcode update: the shim keeps its old mtime but now fails.
  # The installer writes a git with an old build-time mtime into the bin
  # directory; only the directory's mtime moves (to the install time).
  printf '#!/bin/bash\necho "Xcode license not accepted" >&2\nexit 69\n' > "$CACHED_SYSTEM_GIT"
  touch -t 202001010000 "$CACHED_SYSTEM_GIT"
  : > "$DEV_GIT/git"
  touch -t 202001010000 "$DEV_GIT/git"
  touch -t 203001010000 "$DEV_GIT"
  run env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" \
    DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="$PATH_GIT_DIR:/usr/bin:/bin" "$GIT_WRAPPER" status
  [ "$status" -eq 0 ]
  [[ "$output" == "path-git status" ]]
}

@test "probe cache: an unwritable cache dir still runs git" {
  counting_system_git
  mkdir -p "$TEST_DIR/ro"
  chmod 500 "$TEST_DIR/ro"
  run env -u DOTFILES_REAL_GIT XDG_CACHE_HOME="$TEST_DIR/ro" DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" \
    DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="/usr/bin:/bin" "$GIT_WRAPPER" status
  chmod 700 "$TEST_DIR/ro"
  [ "$status" -eq 0 ]
  [[ "$output" == "system-git status" ]]
}

@test "probe cache: marker names stay distinct for a_b/git and a/b/git" {
  mkdir -p "$TEST_DIR/a_b" "$TEST_DIR/a/b"
  printf '#!/bin/bash\necho ok\n' > "$TEST_DIR/a_b/git"
  printf '#!/bin/bash\necho ok\n' > "$TEST_DIR/a/b/git"
  chmod +x "$TEST_DIR/a_b/git" "$TEST_DIR/a/b/git"
  for d in a_b a/b; do
    env -u DOTFILES_REAL_GIT DOTFILES_SYSTEM_GIT="$TEST_DIR/$d/git" DOTFILES_GIT_PROBE_DEPS= \
      PATH="/usr/bin:/bin" "$GIT_WRAPPER" status >/dev/null
  done
  [ "$(ls "$XDG_CACHE_HOME/dotfiles/git-probe" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "probe cache: a caller-set HOME gets no marker" {
  # A tool that runs git with HOME inside a repo must not find a new
  # file there (agentbrew verify-changed.test.ts saw .home/.cache/...).
  counting_system_git
  mkdir -p "$TEST_DIR/fake-home"
  run env -u DOTFILES_REAL_GIT -u XDG_CACHE_HOME HOME="$TEST_DIR/fake-home" USER=no-such-user-dotfiles \
    DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="/usr/bin:/bin" "$GIT_WRAPPER" status
  [ "$status" -eq 0 ]
  [[ "$output" == "system-git status" ]]
  [ ! -e "$TEST_DIR/fake-home/.cache" ]
}

@test "probe cache: a numeric USER never puts a marker in the current dir" {
  # In bash, ~0 and ~-0 are directory-stack forms that expand to $PWD.
  counting_system_git
  mkdir -p "$TEST_DIR/cwd"
  cd "$TEST_DIR/cwd"
  for u in 0 -0; do
    run env -u DOTFILES_REAL_GIT -u XDG_CACHE_HOME HOME="$TEST_DIR/cwd/.home" USER="$u" \
      DOTFILES_SYSTEM_GIT="$CACHED_SYSTEM_GIT" DOTFILES_GIT_PROBE_DEPS="$DEV_GIT" PATH="/usr/bin:/bin" "$GIT_WRAPPER" status
    [ "$status" -eq 0 ]
    [[ "$output" == "system-git status" ]]
  done
  [ ! -e "$TEST_DIR/cwd/.cache" ]
  [ ! -e "$TEST_DIR/cwd/.home" ]
}

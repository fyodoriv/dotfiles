#!/usr/bin/env bats
# Tests for the public-push allowlist that bin/git enforces.
#
# bin/git blocks agent-authored pushes to public repositories unless the
# normalized remote appears in config/public-mirror-remotes.txt. That file is a
# security boundary with no test coverage until now: an accidental wildcard or a
# stray entry would widen what agent pushes can reach on public GitHub with
# nothing objecting.

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  ALLOWLIST="$REPO_ROOT/config/public-mirror-remotes.txt"

  # Source the two wrapper functions under test rather than reimplementing them,
  # so the test tracks bin/git instead of drifting from it.
  SCRIPT_DIR="$REPO_ROOT/bin"
  PUBLIC_MIRROR_ALLOWLIST="$ALLOWLIST"
  export SCRIPT_DIR PUBLIC_MIRROR_ALLOWLIST
  eval "$(sed -n '/^_git_public_repository_key()/,/^}/p;/^_git_public_repository_allowed()/,/^}/p' "$SCRIPT_DIR/git")"
}

@test "allowlist file exists and is readable" {
  [ -r "$ALLOWLIST" ]
}

@test "every listed entry is owner-scoped, never a bare host or wildcard" {
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [ -n "$line" ] || continue
    # host/owner/name — exactly two slashes, no glob characters.
    [[ "$line" == */*/* ]]
    [[ "$line" != */*/*/* ]]
    [[ "$line" != *"*"* ]]
    [[ "$line" != *"?"* ]]
  done < "$ALLOWLIST"
}

@test "a listed repository is allowed" {
  run _git_public_repository_allowed "https://github.com/fyodoriv/dotfiles.git"
  [ "$status" -eq 0 ]
}

@test "the minsky mirror is allowed" {
  run _git_public_repository_allowed "https://github.com/fyodoriv/minsky.git"
  [ "$status" -eq 0 ]
}

@test "an unlisted repository under a listed owner is blocked" {
  run _git_public_repository_allowed "https://github.com/fyodoriv/not-listed.git"
  [ "$status" -ne 0 ]
}

@test "a repository under a different owner is blocked" {
  run _git_public_repository_allowed "https://github.com/someone/evil.git"
  [ "$status" -ne 0 ]
}

@test "the bare host is never allowed" {
  run _git_public_repository_allowed "https://github.com/"
  [ "$status" -ne 0 ]
}

@test "ssh and https forms of a listed repo resolve the same" {
  run _git_public_repository_allowed "git@github.com:fyodoriv/minsky.git"
  [ "$status" -eq 0 ]
}

@test "the retired mirror-setup repository is not allowed" {
  run _git_public_repository_allowed "https://github.com/fyodoriv/mirror-setup.git"
  [ "$status" -ne 0 ]
}

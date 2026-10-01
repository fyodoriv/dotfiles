#!/usr/bin/env bats
# Tests for pre-push hook delegation.

load test_helper

HOOK="$BATS_TEST_DIRNAME/../git-hooks/pre-push"

setup() {
  TEST_DIR="$(mktemp -d)"
  PRIVATE_ENV_FILE="$TEST_DIR/private-email.env"
  EMPTY_ENV_FILE="$TEST_DIR/empty.env"
  cat > "$PRIVATE_ENV_FILE" <<'EOF'
OSS_READINESS_PRIVATE_EMAIL_PATTERN='@private\.example$'
EOF
  : > "$EMPTY_ENV_FILE"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_make_repo() {
  local repo="$1" email="$2"
  mkdir -p "$TEST_DIR/no-hooks"
  git init --quiet "$repo"
  git -C "$repo" config core.hooksPath "$TEST_DIR/no-hooks"
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config user.name "Privacy Test"
  git -C "$repo" config user.email "$email"
  printf 'fixture\n' > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit --quiet -m "test: fixture"
}

_run_pre_push() {
  local repo="$1" remote_name="$2" remote_url="$3"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"
  env OSS_READINESS_ENV_FILE="$PRIVATE_ENV_FILE" \
    bash -c 'cd "$1" && "$2" "$3" "$4" <<EOF
refs/heads/main $5 refs/heads/main 0000000000000000000000000000000000000000
EOF
' _ "$repo" "$HOOK" "$remote_name" "$remote_url" "$sha"
}

@test "pre-push delegates to executable repo-local hooks/pre-push" {
  local repo="$TEST_DIR/repo"
  git init --quiet "$repo"
  mkdir -p "$repo/hooks"
  cat > "$repo/hooks/pre-push" <<'SCRIPT'
#!/bin/bash
echo "repo-local pre-push ran remote=$1 url=$2" >&2
exit 44
SCRIPT
  chmod +x "$repo/hooks/pre-push"

  run bash -c 'cd "$1" && "$2" origin git@example.com:repo.git' _ "$repo" "$HOOK"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo-local pre-push ran remote=origin url=git@example.com:repo.git"* ]]
}

@test "pre-push succeeds when repo has no local hook" {
  local repo="$TEST_DIR/no-hook"
  git init --quiet "$repo"

  run bash -c 'cd "$1" && "$2" origin git@example.com:repo.git' _ "$repo" "$HOOK"
  [ "$status" -eq 0 ]
}

@test "pre-push gate passes a dotfiles-shaped repo with no private env" {
  local repo="$TEST_DIR/dotfiles-shaped"
  _make_repo "$repo" "public@example.test"
  mkdir -p "$repo/lib"
  : > "$repo/lib/oss-readiness.sh"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"

  run env -u OSS_READINESS_INTERNAL_PATTERN -u OSS_READINESS_PRIVATE_EMAIL_PATTERN OSS_READINESS_ENV_FILE="$EMPTY_ENV_FILE" bash -c 'cd "$1" && "$2" origin git@example.com:repo.git <<EOF
refs/heads/main $3 refs/heads/main 0000000000000000000000000000000000000000
EOF' _ "$repo" "$HOOK" "$sha"
  [ "$status" -eq 0 ]
}

@test "pre-push permits a public identity to the GitHub.com origin" {
  local repo="$TEST_DIR/agentbrew"
  _make_repo "$repo" "public@example.test"

  run _run_pre_push "$repo" origin "https://github.com/fyodoriv/agentbrew.git"

  [ "$status" -eq 0 ]
}

@test "pre-push blocks a private identity to the GitHub.com origin (HTTPS)" {
  local repo="$TEST_DIR/agentbrew"
  _make_repo "$repo" "author@private.example"

  run _run_pre_push "$repo" origin "https://github.com/fyodoriv/agentbrew.git"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Private author or committer emails"* ]]
}

@test "pre-push blocks a private identity to the GitHub.com origin (SSH)" {
  local repo="$TEST_DIR/dotfiles"
  _make_repo "$repo" "author@private.example"

  run _run_pre_push "$repo" origin "git@github.com:fyodoriv/dotfiles.git"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Private author or committer emails"* ]]
}

@test "pre-push gates every remote name that points at the GitHub.com repo" {
  local repo="$TEST_DIR/agentbrew"
  _make_repo "$repo" "author@private.example"

  run _run_pre_push "$repo" upstream "git@github.com:fyodoriv/agentbrew.git"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Private author or committer emails"* ]]
}

@test "pre-push defers for unrelated repositories" {
  local repo="$TEST_DIR/other"
  _make_repo "$repo" "author@private.example"

  run _run_pre_push "$repo" origin "git@github.com:someone/other.git"

  [ "$status" -eq 0 ]
}

@test "pre-push permits pushes when no private-email pattern is configured" {
  local repo="$TEST_DIR/agentbrew"
  _make_repo "$repo" "author@private.example"
  local sha
  sha="$(git -C "$repo" rev-parse HEAD)"

  run env -u OSS_READINESS_PRIVATE_EMAIL_PATTERN OSS_READINESS_ENV_FILE="$EMPTY_ENV_FILE" bash -c 'cd "$1" && "$2" "$3" "$4" <<EOF
refs/heads/main $5 refs/heads/main 0000000000000000000000000000000000000000
EOF
' _ "$repo" "$HOOK" origin "https://github.com/fyodoriv/agentbrew.git" "$sha"

  [ "$status" -eq 0 ]
}

# ── Private-reference content gate ─────────────────────────────────────

_pattern_env() {
  printf "OSS_READINESS_INTERNAL_PATTERN='%s'\n" "$1" > "$TEST_DIR/pattern.env"
}

_push_range() {
  # $1 repo, $2 remote name, $3 local sha, $4 remote sha
  run env OSS_READINESS_ENV_FILE="$TEST_DIR/pattern.env" bash -c 'cd "$1" && "$2" "$3" "$4" <<EOF
refs/heads/topic $5 refs/heads/topic $6
EOF
' _ "$1" "$HOOK" "$2" "https://github.com/fyodoriv/dotfiles.git" "$3" "$4"
}

_commit_file() {
  # $1 repo, $2 file, $3 content
  printf '%s\n' "$3" > "$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit --quiet -m "docs: add $2"
}

@test "pre-push blocks when a pushed file matches the private pattern" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" notes.md "see company-private wiki"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -ne 0 ]
  [[ "$output" == *"notes.md"* ]]
  [[ "$output" != *"company-private"* ]]
}

@test "pre-push allows a clean push when a pattern is configured" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" notes.md "nothing to see"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -eq 0 ]
}

@test "pre-push ignores matches in files outside the pushed range" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  _commit_file "$repo" old.md "company-private old"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" new.md "clean"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -eq 0 ]
}

@test "pre-push new-branch push scans only commits no remote ref has" {
  local repo="$TEST_DIR/repo"
  _make_repo "$repo" "public@example.test"
  _commit_file "$repo" old.md "company-private old"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  _commit_file "$repo" bad.md "bad company-private"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" 0000000000000000000000000000000000000000

  [ "$status" -ne 0 ]
  [[ "$output" == *"bad.md"* ]]
  [[ "$output" != *"old.md"* ]]
}

@test "pre-push new-branch push with no new commits scans the whole tree" {
  local repo="$TEST_DIR/repo"
  _make_repo "$repo" "public@example.test"
  _commit_file "$repo" tracked.md "company-private here"
  git -C "$repo" update-ref refs/remotes/origin/main HEAD
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" 0000000000000000000000000000000000000000

  [ "$status" -ne 0 ]
  [[ "$output" == *"tracked.md"* ]]
}

@test "pre-push allows a matching file when no pattern is configured" {
  local repo="$TEST_DIR/repo" sha
  _make_repo "$repo" "public@example.test"
  _commit_file "$repo" notes.md "company-private"
  sha="$(git -C "$repo" rev-parse HEAD)"

  run env -u OSS_READINESS_INTERNAL_PATTERN OSS_READINESS_ENV_FILE="$EMPTY_ENV_FILE" bash -c 'cd "$1" && "$2" origin "https://github.com/fyodoriv/dotfiles.git" <<EOF
refs/heads/topic $3 refs/heads/topic 0000000000000000000000000000000000000000
EOF
' _ "$repo" "$HOOK" "$sha"

  [ "$status" -eq 0 ]
}

@test "pre-push blocks a commit that adds a private reference a later commit removed" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" notes.md "see company-private wiki"
  _commit_file "$repo" notes.md "nothing to see"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -ne 0 ]
  [[ "$output" == *"commit(s) in the push add lines"* ]]
  [[ "$output" != *"company-private"* ]]
}

_roots_env() {
  printf "OSS_READINESS_ALLOWED_ROOTS='%s'\n" "$1" > "$TEST_DIR/pattern.env"
}

@test "pre-push allows history that starts at an approved root" {
  local repo="$TEST_DIR/repo" root
  _make_repo "$repo" "public@example.test"
  root="$(git -C "$repo" rev-list --max-parents=0 HEAD)"
  _commit_file "$repo" notes.md "clean"
  _roots_env "deadbeef $root"

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" 0000000000000000000000000000000000000000

  [ "$status" -eq 0 ]
}

@test "pre-push blocks history from an unapproved root" {
  local repo="$TEST_DIR/repo"
  _make_repo "$repo" "public@example.test"
  _commit_file "$repo" notes.md "clean"
  _roots_env "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" 0000000000000000000000000000000000000000

  [ "$status" -ne 0 ]
  [[ "$output" == *"unapproved root commit"* ]]
}

# ── Every listed public repo, file names, and commit messages ──────────

@test "pre-push gates every public repo in the push allowlist" {
  local repo="$TEST_DIR/repo"
  _make_repo "$repo" "dev@private.example"

  run _run_pre_push "$repo" origin "https://github.com/fyodoriv/minsky.git"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Private author or committer emails"* ]]
}

@test "pre-push blocks a pushed file whose name matches the private pattern" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" company-private-ignore.yaml "clean content"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -ne 0 ]
  [[ "$output" != *"company-private"* ]]
}

@test "pre-push blocks a file name that a later commit removed" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  _commit_file "$repo" company-private.md "clean content"
  git -C "$repo" rm --quiet company-private.md
  git -C "$repo" commit --quiet -m "docs: remove file"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -ne 0 ]
}

@test "pre-push blocks a commit message that matches the private pattern" {
  local repo="$TEST_DIR/repo" base
  _make_repo "$repo" "public@example.test"
  base="$(git -C "$repo" rev-parse HEAD)"
  printf 'clean\n' > "$repo/notes.md"
  git -C "$repo" add notes.md
  git -C "$repo" commit --quiet -m "docs: notes from the company-private wiki"
  _pattern_env 'company-private'

  _push_range "$repo" origin "$(git -C "$repo" rev-parse HEAD)" "$base"

  [ "$status" -ne 0 ]
  [[ "$output" != *"company-private"* ]]
}

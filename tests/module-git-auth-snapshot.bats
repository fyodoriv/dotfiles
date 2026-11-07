#!/usr/bin/env bats

load test_helper

MODULE="$BATS_TEST_DIRNAME/../modules/git/doctor.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/gitconfig-user-migrate.sh" \
    "$BATS_TEST_DIRNAME/../lib/xcode-license.sh" "$TEST_DOTFILES/lib/"
  export HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_REPOS_DIR="$TEST_DIR/repos"
  export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
  touch "$GIT_CONFIG_GLOBAL"
  export GH_AUTH_FIXTURE_LOG="$TEST_DIR/auth-calls"
  GH_AUTH_FIXTURE_ARGS="$TEST_DIR/auth-args"
  CHECK_RESULTS="$TEST_DIR/check-results"
  : > "$GH_AUTH_FIXTURE_LOG"
  : > "$GH_AUTH_FIXTURE_ARGS"
  : > "$CHECK_RESULTS"
  GH_AUTH_FIXTURE_RC=0
  GH_AUTH_FIXTURE_OUTPUT='Token scopes: repo, gist, read:org, workflow, admin:public_key, delete_repo'
  GH_AUTH_ACTIVE_OUTPUT=''
  GH_ADMIN_SCOPES=false
  IS_ENTERPRISE=false
  FIX_MODE=false
  LIST_MODE=false
  OVERRIDE_AUTH_CHECKS=false
  OVERRIDE_AUTH_ONLY=false

  gh() {
    case "$*" in
      'auth status -h github.com'|'auth status -h github.com --active')
        printf 'probe\n' >> "$GH_AUTH_FIXTURE_LOG"
        printf '%s\n' "$*" >> "$GH_AUTH_FIXTURE_ARGS"
        if [ "$*" = 'auth status -h github.com --active' ] && [ -n "$GH_AUTH_ACTIVE_OUTPUT" ]; then
          printf '%s\n' "$GH_AUTH_ACTIVE_OUTPUT"
        else
          printf '%s\n' "$GH_AUTH_FIXTURE_OUTPUT"
        fi
        return "$GH_AUTH_FIXTURE_RC"
        ;;
      *) return 0 ;;
    esac
  }
  chezmoi() { printf 'false\n'; }
  check_managed() { :; }
  check_symlink() { :; }
  check() {
    local id="$1" test_cmd="$3" result
    $LIST_MODE && return 0
    $OVERRIDE_AUTH_CHECKS && return 0
    case "$id" in git.gh_auth|git.gh_scope.*) ;; *) return 0 ;; esac
    if [ "$id" = git.gh_auth ] && $OVERRIDE_AUTH_ONLY; then return 0; fi
    if eval "$test_cmd" >/dev/null 2>&1; then result=0; else result=$?; fi
    printf '%s:%s\n' "$id" "$result" >> "$CHECK_RESULTS"
  }
}

@test "git auth snapshot probes once while retaining normal auth and scope checks" {
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$CHECK_RESULTS" | tr -d ' ')" -eq 4 ]
  ! grep -v ':0$' "$CHECK_RESULTS"
}

@test "git auth snapshot probes once for admin scope checks" {
  GH_ADMIN_SCOPES=true
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$CHECK_RESULTS" | tr -d ' ')" -eq 7 ]
  ! grep -v ':0$' "$CHECK_RESULTS"
}

@test "git auth snapshot retains a failed authentication exit code" {
  set +o pipefail
  GH_AUTH_FIXTURE_RC=1
  source "$MODULE"
  grep -qx 'git.gh_auth:1' "$CHECK_RESULTS"
  grep -qx 'git.gh_scope.repo:0' "$CHECK_RESULTS"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
}

@test "git auth snapshot preserves scope pipeline failure with pipefail enabled" {
  set -o pipefail
  GH_AUTH_FIXTURE_RC=1
  source "$MODULE"
  grep -qx 'git.gh_auth:1' "$CHECK_RESULTS"
  grep -qx 'git.gh_scope.repo:1' "$CHECK_RESULTS"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
}

@test "git auth snapshot reports a missing scope" {
  GH_AUTH_FIXTURE_OUTPUT='Token scopes: repo, gist'
  source "$MODULE"
  grep -qx 'git.gh_auth:0' "$CHECK_RESULTS"
  grep -qx 'git.gh_scope.read:org:1' "$CHECK_RESULTS"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
}

scope_active_checked() {
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  grep -qx 'auth status -h github.com --active' "$GH_AUTH_FIXTURE_ARGS"
}

@test "scope exact rejects delete_repo as repo" {
  GH_AUTH_FIXTURE_OUTPUT='Token scopes: delete_repo, gist, read:org'
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  grep -qx 'git.gh_scope.repo:1' "$CHECK_RESULTS" || { echo 'false repo grant'; return 1; }
  scope_active_checked
}

@test "scope exact ignores non-scope text" {
  GH_AUTH_FIXTURE_OUTPUT=$'Token scopes: repo, read:org\ngist not granted'
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  grep -qx 'git.gh_scope.gist:1' "$CHECK_RESULTS" || { echo 'false gist grant'; return 1; }
  scope_active_checked
}

@test "scope exact rejects longer org name" {
  GH_AUTH_FIXTURE_OUTPUT='Token scopes: repo, gist, read:organization'
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  grep -qx 'git.gh_scope.read:org:1' "$CHECK_RESULTS" || { echo 'false org grant'; return 1; }
  scope_active_checked
}

scope_all_granted() {
  source "$MODULE"
  for scope in repo gist read:org; do grep -qx "git.gh_scope.$scope:0" "$CHECK_RESULTS" || return 1; done
  scope_active_checked
}

@test "scope exact accepts bare names" {
  GH_AUTH_FIXTURE_OUTPUT='  - Token scopes: repo, gist, read:org'
  scope_all_granted
}

@test "scope exact accepts quoted names" {
  GH_AUTH_FIXTURE_OUTPUT="  - Token scopes: 'repo', 'gist', 'read:org'"
  scope_all_granted
}

@test "scope exact accepts double-quoted names" {
  GH_AUTH_FIXTURE_OUTPUT='  - Token scopes: "repo", "gist", "read:org"'
  scope_all_granted
}

@test "scope exact selects active account" {
  GH_AUTH_FIXTURE_OUTPUT=$'Active account: false\nToken scopes: repo, gist, read:org\nActive account: true\nToken scopes: gist, read:org'
  GH_AUTH_ACTIVE_OUTPUT='  - Token scopes: gist, read:org'
  source "$MODULE"
  grep -qx 'git.gh_scope.repo:1' "$CHECK_RESULTS"
  scope_active_checked
}

@test "scope exact rejects ambiguous evidence" {
  for value in 'Fine-grained token' $'Token scopes: repo, gist, read:org\nToken scopes: repo' "Token scopes: 'repo', 'gist" 'Token scopes:' 'Token scopes: repo, @invalid, gist'; do
    GH_AUTH_FIXTURE_OUTPUT="$value"
    : > "$CHECK_RESULTS"
    : > "$GH_AUTH_FIXTURE_LOG"
    : > "$GH_AUTH_FIXTURE_ARGS"
    source "$MODULE"
    for scope in repo gist read:org; do grep -qx "git.gh_scope.$scope:1" "$CHECK_RESULTS" || return 1; done
    scope_active_checked
  done
  GH_AUTH_FIXTURE_OUTPUT='unknown flag: --active'
  GH_AUTH_FIXTURE_RC=1
  : > "$CHECK_RESULTS"
  : > "$GH_AUTH_FIXTURE_LOG"
  : > "$GH_AUTH_FIXTURE_ARGS"
  source "$MODULE"
  grep -qx 'git.gh_auth:1' "$CHECK_RESULTS"
  for scope in repo gist read:org; do grep -qx "git.gh_scope.$scope:1" "$CHECK_RESULTS" || return 1; done
  scope_active_checked
}

@test "git auth snapshot does not probe while listing check IDs" {
  LIST_MODE=true
  source "$MODULE"
  [ ! -s "$GH_AUTH_FIXTURE_LOG" ]
}

@test "git auth snapshot does not probe when every auth check is overridden" {
  OVERRIDE_AUTH_CHECKS=true
  source "$MODULE"
  [ ! -s "$GH_AUTH_FIXTURE_LOG" ]
}

@test "git auth snapshot keeps fix-mode probes fresh" {
  FIX_MODE=true
  GH_ADMIN_SCOPES=true
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 7 ]
}

@test "git auth snapshot refreshes on the next module run" {
  source "$MODULE"
  : > "$CHECK_RESULTS"
  GH_AUTH_FIXTURE_OUTPUT='Token scopes: repo, gist'
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 2 ]
  grep -qx 'git.gh_scope.read:org:1' "$CHECK_RESULTS"
}


@test "git auth snapshot initializes from a scope check when auth is overridden" {
  OVERRIDE_AUTH_ONLY=true
  source "$MODULE"
  [ "$(wc -l < "$GH_AUTH_FIXTURE_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(wc -l < "$CHECK_RESULTS" | tr -d ' ')" -eq 3 ]
  ! grep -v ':0$' "$CHECK_RESULTS"
}

stale_token_check() {
  # Fixture: the keyring login is valid; only the token "good" is valid.
  gh() {
    [ "$*" = 'auth status -h github.com' ] || return 0
    [ -z "${GITHUB_TOKEN:-}" ] || [ "$GITHUB_TOKEN" = good ]
  }
  check() {
    local id="$1" test_cmd="$3" result
    case "$id" in git.gh_env_token|git.gh_launchctl_token) ;; *) return 0 ;; esac
    if eval "$test_cmd" >/dev/null 2>&1; then result=0; else result=1; fi
    printf '%s:%s\n' "$id" "$result" >> "$CHECK_RESULTS"
  }
  source "$MODULE"
}

@test "stale GITHUB_TOKEN fails the env token check" {
  export GITHUB_TOKEN=stale
  stale_token_check
  grep -qx 'git.gh_env_token:1' "$CHECK_RESULTS"
}

@test "valid or unset GITHUB_TOKEN passes the env token check" {
  export GITHUB_TOKEN=good
  stale_token_check
  grep -qx 'git.gh_env_token:0' "$CHECK_RESULTS"
  : > "$CHECK_RESULTS"
  unset GITHUB_TOKEN
  stale_token_check
  grep -qx 'git.gh_env_token:0' "$CHECK_RESULTS"
}

@test "stale launchctl GITHUB_TOKEN fails the GUI token check" {
  launchctl() { [ "$*" = 'getenv GITHUB_TOKEN' ] && printf 'stale\n'; }
  unset GITHUB_TOKEN
  stale_token_check
  grep -qx 'git.gh_launchctl_token:1' "$CHECK_RESULTS"
}

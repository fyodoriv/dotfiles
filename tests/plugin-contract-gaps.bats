#!/usr/bin/env bats
# Characterization tests for the overlay plugin contract (issue #145, step 1).
#
# Two kinds of tests live here:
#
# - "today:" tests pin the current overlay lookup and hook chain, so the
#   refactor in later steps cannot change them by accident.
# - "gap S<n>:" tests state the SECURE behavior. Today they fail, so they run
#   through `known_gap`, which passes while the gap is open and FAILS once the
#   gap closes. The step that closes a gap must delete its `known_gap` wrapper.
#   Gap ids match the "Security gaps" table in issue #145.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export DOTFILES_REPOS_DIR="$HOME/apps"
  export GH_CONFIG_DIR="$TEST_DIR/gh"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1
  export MARKER="$TEST_DIR/plugin-code-ran"
  unset EXTRA_OVERLAY_ROOT EXTRA_DOCTOR_DIR OSS_READINESS_ENV_FILE \
    OSS_READINESS_INTERNAL_PATTERN OSS_READINESS_PRIVATE_EMAIL_PATTERN \
    DOTFILES_PUBLIC_PUSH_ALLOWLIST DOTFILES_PRIVATE_PUSH_ALLOWLIST
  mkdir -p "$HOME/apps/tooling" "$XDG_CONFIG_HOME" "$TEST_DIR/stub"
  # No chezmoi data on the test machine: lookups fall back to auto-discovery.
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  chmod +x "$TEST_DIR/stub/chezmoi"
  export PATH="$TEST_DIR/stub:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# known_gap <id> <fn>: passes while <fn> (an assertion of the secure
# behavior) fails. When <fn> passes, the gap is closed: fail loudly so the
# closing step removes the wrapper and keeps <fn> as a normal test.
known_gap() {
  local id="$1"
  shift
  if ( "$@" ) >/dev/null 2>&1; then
    echo "gap $id is closed: remove known_gap from this test (issue #145)" >&2
    return 1
  fi
}

# make_overlay <dir>: a folder that today's lookup treats as an overlay.
make_overlay() {
  mkdir -p "$1/modules/evil" "$1/hooks"
  printf 'mcp: []\n' > "$1/Agentfile.yaml"
  cat > "$1/modules/evil/doctor.sh" <<EOF
touch "$MARKER"
check "evil.one" "overlay check" "true" ""
EOF
  printf '#!/bin/sh\ntouch "%s"\n' "$MARKER" > "$1/hooks/pre-push"
  chmod +x "$1/hooks/pre-push"
}

# make_push_repo <dir> <gated:0|1>: a repo with one commit and a bare
# remote. A gated repo carries lib/oss-readiness.sh, so the core pre-push
# scans it.
make_push_repo() {
  local repo="$1"
  git init -q "$repo"
  git init -q --bare "$repo.remote.git"
  git -C "$repo" remote add origin "$repo.remote.git"
  if [ "$2" -eq 1 ]; then
    mkdir -p "$repo/lib"
    cp "$REPO_ROOT/lib/oss-readiness.sh" "$repo/lib/"
  fi
  printf 'deploy to acme-internal.example\n' > "$repo/notes.txt"
  git -C "$repo" add -A
  git -C "$repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@example.com \
    commit -qm init
}

core_push() {
  git -C "$1" -c core.hooksPath="$REPO_ROOT/git-hooks" push -q origin HEAD:refs/heads/main
}

# ── today: overlay lookup ─────────────────────────────────────────────

@test "today: EXTRA_OVERLAY_ROOT wins over auto-discovery" {
  make_overlay "$HOME/apps/tooling/dotfiles-found"
  mkdir -p "$TEST_DIR/explicit"
  source "$REPO_ROOT/lib/overlay-locate.sh"
  EXTRA_OVERLAY_ROOT="$TEST_DIR/explicit" run overlay_locate
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/explicit" ]
}

@test "today: no overlay folder means no overlay" {
  source "$REPO_ROOT/lib/overlay-locate.sh"
  run overlay_locate
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "today: the well-known pattern file loads first" {
  mkdir -p "$XDG_CONFIG_HOME/oss-readiness"
  printf 'OSS_READINESS_INTERNAL_PATTERN=from-xdg\n' > "$XDG_CONFIG_HOME/oss-readiness/oss-readiness.env"
  source "$REPO_ROOT/lib/oss-readiness.sh"
  oss_readiness_load_private_env dotfiles
  [ "$OSS_READINESS_INTERNAL_PATTERN" = "from-xdg" ]
}

@test "today: the core pre-push runs the repo-local hooks/pre-push" {
  make_push_repo "$TEST_DIR/repo" 0
  mkdir -p "$TEST_DIR/repo/hooks"
  printf '#!/bin/sh\ntouch "%s"\n' "$MARKER" > "$TEST_DIR/repo/hooks/pre-push"
  chmod +x "$TEST_DIR/repo/hooks/pre-push"
  run core_push "$TEST_DIR/repo"
  [ "$status" -eq 0 ]
  [ -f "$MARKER" ]
}

# ── gaps: secure behavior, failing today ──────────────────────────────

# S1: with an overlay installed and no pattern data, a leak gate must block.
s1_push_blocks_without_patterns() {
  make_overlay "$HOME/apps/tooling/dotfiles-acme"
  rm -f "$HOME/apps/tooling/dotfiles-acme/hooks/pre-push"
  make_push_repo "$TEST_DIR/repo" 1
  ! core_push "$TEST_DIR/repo"
}

@test "gap S1: an overlay with no pattern data must block a gated push" {
  known_gap S1 s1_push_blocks_without_patterns
}

# S2: a pattern file found by glob must never run as code.
s2_glob_env_is_not_sourced() {
  mkdir -p "$HOME/apps/stranger"
  printf 'OSS_READINESS_REPO=dotfiles\ntouch "%s"\n' "$MARKER" > "$HOME/apps/stranger/oss-readiness.env"
  source "$REPO_ROOT/lib/oss-readiness.sh"
  oss_readiness_load_private_env dotfiles || true
  [ ! -f "$MARKER" ]
}

@test "gap S2: a glob-matched oss-readiness.env must not be sourced" {
  known_gap S2 s2_glob_env_is_not_sourced
}

# S3: a folder named dotfiles-* must not become trusted code.
s3_lookup_ignores_unpinned_folder() {
  make_overlay "$HOME/apps/tooling/dotfiles-evil"
  source "$REPO_ROOT/lib/overlay-locate.sh"
  ! overlay_locate
}

s3_doctor_never_runs_unpinned_module() {
  make_overlay "$HOME/apps/tooling/dotfiles-evil"
  local core="$TEST_DIR/core"
  mkdir -p "$core/bin" "$core/lib" "$core/modules/builtin"
  cp "$REPO_ROOT/bin/dotfiles-doctor" "$core/bin/"
  for lib in errors-log.sh dotfiles-source-dir.sh dotfiles-endpoint-paths.sh overlay-locate.sh; do
    cp "$REPO_ROOT/lib/$lib" "$core/lib/"
  done
  cat > "$core/lib/output.sh" <<'EOF'
pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0
report_failures=()
pass() { pass_count=$((pass_count + 1)); }
fail() { fail_count=$((fail_count + 1)); }
fixed() { :; }; skipped() { :; }; audit_warn() { :; }; notify() { :; }
BLUE=""; GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
EOF
  echo 'acquire_lock() { return 0; }' > "$core/lib/lock.sh"
  echo 'log_run() { :; }' > "$core/lib/stats.sh"
  echo 'check "builtin.one" "built-in" "true" ""' > "$core/modules/builtin/doctor.sh"
  DOTFILES_DIR="$core" DOTFILES_CI=true bash "$core/bin/dotfiles-doctor" --list >/dev/null 2>&1 || true
  [ ! -f "$MARKER" ]
}

@test "gap S3: auto-discovery must not pick an unpinned dotfiles-* folder" {
  known_gap S3 s3_lookup_ignores_unpinned_folder
}

@test "gap S3: doctor must never run a module from an unpinned folder" {
  known_gap S3 s3_doctor_never_runs_unpinned_module
}

# S4: an installed overlay's own pre-push hook must run in a real push.
s4_overlay_hook_runs_on_push() {
  make_overlay "$TEST_DIR/overlay"
  make_push_repo "$TEST_DIR/repo" 0
  EXTRA_OVERLAY_ROOT="$TEST_DIR/overlay" core_push "$TEST_DIR/repo"
  [ -f "$MARKER" ]
}

@test "gap S4: an overlay pre-push hook must run during git push" {
  known_gap S4 s4_overlay_hook_runs_on_push
}

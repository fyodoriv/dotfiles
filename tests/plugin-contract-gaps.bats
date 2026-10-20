#!/usr/bin/env bats
# Characterization tests for the overlay plugin contract (issue #145, step 1).
#
# Two kinds of tests live here:
#
# - "today:" tests pin the current overlay lookup and hook chain, so the
#   refactor in later steps cannot change them by accident.
# - "closed S<n>:" tests state the SECURE behavior for each gap in the
#   "Security gaps" table of issue #145. Steps 1-4 proved and closed S1-S4.

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
  unset OSS_READINESS_ENV_FILE \
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

# install_plugin <dir>: make <dir> a verified dev plugin in plugins.lock,
# with its git hooks declared.
install_plugin() {
  printf 'schema: 1\nname: acme\nversion: 1.0.0\ncapabilities:\n  hooks: [pre-push, pre-commit]\n' \
    > "$1/dotfiles-plugin.yaml"
  bash "$REPO_ROOT/bin/dotfiles-plugin" add --dev "$1" --yes >/dev/null
}

core_push() {
  git -C "$1" -c core.hooksPath="$REPO_ROOT/git-hooks" push -q origin HEAD:refs/heads/main
}

# ── today: overlay lookup ─────────────────────────────────────────────


@test "today: no overlay folder means no overlay" {
  source "$REPO_ROOT/lib/plugin.sh"
  run plugin_overlay_root
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

# ── closed gaps: secure behavior ─────────────────────────────────────────────

# S1: with an overlay installed and no pattern data, a leak gate must block.
s1_push_blocks_without_patterns() {
  make_overlay "$HOME/apps/tooling/dotfiles-acme"
  rm -f "$HOME/apps/tooling/dotfiles-acme/hooks/pre-push"
  install_plugin "$HOME/apps/tooling/dotfiles-acme"
  make_push_repo "$TEST_DIR/repo" 1
  ! core_push "$TEST_DIR/repo"
}

@test "closed S1: an overlay with no pattern data must block a gated push" {
  s1_push_blocks_without_patterns
}

# S2: a pattern file found by glob must never run as code.
s2_glob_env_is_not_sourced() {
  mkdir -p "$HOME/apps/stranger"
  printf 'OSS_READINESS_REPO=dotfiles\ntouch "%s"\n' "$MARKER" > "$HOME/apps/stranger/oss-readiness.env"
  source "$REPO_ROOT/lib/oss-readiness.sh"
  oss_readiness_load_private_env dotfiles || true
  [ ! -f "$MARKER" ]
}

@test "closed S2: a glob-matched oss-readiness.env must not be sourced" {
  s2_glob_env_is_not_sourced
}

# S3: a folder named dotfiles-* must not become trusted code.
s3_lookup_ignores_unpinned_folder() {
  make_overlay "$HOME/apps/tooling/dotfiles-evil"
  source "$REPO_ROOT/lib/plugin.sh"
  ! plugin_overlay_root
}

s3_doctor_never_runs_unpinned_module() {
  make_overlay "$HOME/apps/tooling/dotfiles-evil"
  local core="$TEST_DIR/core"
  mkdir -p "$core/bin" "$core/lib" "$core/modules/builtin"
  cp "$REPO_ROOT/bin/dotfiles-doctor" "$core/bin/"
  for lib in errors-log.sh dotfiles-source-dir.sh dotfiles-endpoint-paths.sh plugin.sh; do
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

@test "closed S3: auto-discovery must not pick an unpinned dotfiles-* folder" {
  s3_lookup_ignores_unpinned_folder
}

@test "closed S3: doctor must never run a module from an unpinned folder" {
  s3_doctor_never_runs_unpinned_module
}

# S4: an installed overlay's own pre-push hook must run in a real push.
s4_overlay_hook_runs_on_push() {
  make_overlay "$TEST_DIR/overlay"
  make_push_repo "$TEST_DIR/repo" 0
  install_plugin "$TEST_DIR/overlay"
  core_push "$TEST_DIR/repo"
  [ -f "$MARKER" ]
}

@test "closed S4: an overlay pre-push hook must run during git push" {
  s4_overlay_hook_runs_on_push
}

s1_commit_blocks_without_patterns() {
  make_overlay "$HOME/apps/tooling/dotfiles-acme"
  install_plugin "$HOME/apps/tooling/dotfiles-acme"
  make_push_repo "$TEST_DIR/repo" 1
  printf 'more\n' >> "$TEST_DIR/repo/notes.txt"
  git -C "$TEST_DIR/repo" add notes.txt
  run git -C "$TEST_DIR/repo" -c core.hooksPath="$REPO_ROOT/git-hooks" \
    -c user.name=t -c user.email=t@example.com commit -qm "chore: more"
  [ "$status" -ne 0 ] && [[ "$output" == *"overlay is installed"* ]]
}

@test "closed S1: an overlay with no pattern data must block a gated commit" {
  s1_commit_blocks_without_patterns
}

@test "S1: a gated push goes through when the overlay pattern loads" {
  make_overlay "$HOME/apps/tooling/dotfiles-acme"
  rm -f "$HOME/apps/tooling/dotfiles-acme/hooks/pre-push"
  install_plugin "$HOME/apps/tooling/dotfiles-acme"
  printf "OSS_READINESS_INTERNAL_PATTERN='zz-not-in-repo'\n" > "$HOME/apps/tooling/dotfiles-acme/oss-readiness.env"
  make_push_repo "$TEST_DIR/repo" 1
  run core_push "$TEST_DIR/repo"
  [ "$status" -eq 0 ]
}

@test "S4: a failing overlay pre-push hook blocks the push and gets the payload" {
  make_overlay "$TEST_DIR/overlay"
  printf '#!/bin/sh\ncat > "%s"\nexit 7\n' "$MARKER" > "$TEST_DIR/overlay/hooks/pre-push"
  make_push_repo "$TEST_DIR/repo" 0
  install_plugin "$TEST_DIR/overlay"
  run core_push "$TEST_DIR/repo"
  [ "$status" -ne 0 ]
  grep -q 'refs/heads/main' "$MARKER"
}

@test "S4: an overlay pre-commit hook runs during git commit" {
  make_overlay "$TEST_DIR/overlay"
  printf '#!/bin/sh\ntouch "%s"\n' "$MARKER" > "$TEST_DIR/overlay/hooks/pre-commit"
  chmod +x "$TEST_DIR/overlay/hooks/pre-commit"
  make_push_repo "$TEST_DIR/repo" 0
  printf 'more\n' >> "$TEST_DIR/repo/notes.txt"
  git -C "$TEST_DIR/repo" add notes.txt
  install_plugin "$TEST_DIR/overlay"
  git -C "$TEST_DIR/repo" -c core.hooksPath="$REPO_ROOT/git-hooks" \
    -c user.name=t -c user.email=t@example.com commit -qm "chore: more"
  [ -f "$MARKER" ]
}

@test "step 9: a person's one-time grant for a commit lets that blocked push through once" {
  export XDG_STATE_HOME="$TEST_DIR/state"
  mkdir -p "$TEST_DIR/env"
  printf "OSS_READINESS_INTERNAL_PATTERN='acme-internal'\n" > "$TEST_DIR/env/oss.env"
  export OSS_READINESS_ENV_FILE="$TEST_DIR/env/oss.env"
  make_push_repo "$TEST_DIR/repo" 1
  run core_push "$TEST_DIR/repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dotfiles leak allow --once"* ]]
  mkdir -p "$XDG_STATE_HOME/dotfiles"
  printf '%s %s\n' "$(git -C "$TEST_DIR/repo" rev-parse --short=12 HEAD)" "$(( $(date +%s) + 600 ))" \
    > "$XDG_STATE_HOME/dotfiles/leak-allow-once"
  run core_push "$TEST_DIR/repo"
  [ "$status" -eq 0 ]
  [ ! -f "$XDG_STATE_HOME/dotfiles/leak-allow-once" ]
}

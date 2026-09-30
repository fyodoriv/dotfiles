#!/usr/bin/env bats
# Tests for modules/personal-machine/doctor.sh.
#
# Verifies the personal-machine checks correctly identify the four states
# the operator can land in on the personal Mac:
#   - missing global git identity → fail loud with the exact `git config` fix
#   - git identity is @company.example (corporate leak onto personal machine) → fail
#   - repo paths missing / wrong origin / wrong branch → fail per-repo
#   - all four invariants intact → green
#
# Profile gate test: on a corporate machine (is_enterprise=true) the module
# returns 0 without running any checks — these don't apply to corporate
# setups where the paths and identity are different by policy.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/modules/personal-machine"
  cp "$BATS_TEST_DIRNAME/../modules/personal-machine/doctor.sh" "$TEST_DOTFILES/modules/personal-machine/"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Mock check() machinery (same pattern as other module-* tests).
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"; touch "$OVERRIDES_FILE"
  FIX_MODE=false; LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  pass_msgs=()
  fail_msgs=()
  pass()    { pass_count=$((pass_count + 1)); pass_msgs+=("$1"); }
  fail()    { fail_count=$((fail_count + 1)); fail_msgs+=("$1"); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then eval "$fix_cmd" >/dev/null 2>&1 && fixed "$desc" || fail "$desc"
    else fail "$desc"; fi
  }

  # The module's `git config --global` checks are scoped to the test's HOME
  # via the standard test_helper isolation, BUT `git config --global` reads
  # from `$HOME/.gitconfig` only when `XDG_CONFIG_HOME` doesn't override.
  # Force it to read from our tmp HOME by unsetting any inherited values.
  unset GIT_CONFIG_GLOBAL XDG_CONFIG_HOME
  export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig"

  IS_ENTERPRISE="false"
}

teardown() { rm -rf "$TEST_DIR"; }

# Helper: create a fake git repo at the given path with the given remote URL
# and branch. Skips the working-tree checkout; just enough state for the
# doctor's `git -C` calls to succeed.
make_fake_repo() {
  local path="$1" remote_url="$2" branch="$3"
  mkdir -p "$path"
  git -C "$path" init --quiet --initial-branch="$branch"
  git -C "$path" remote add origin "$remote_url"
  git -C "$path" config user.email "test@example.com"
  git -C "$path" config user.name "Test"
  git -C "$path" config commit.gpgsign false
  git -C "$path" config core.hooksPath /dev/null
  git -C "$path" commit --allow-empty --quiet -m "seed"
}

# ─── Profile gate ──────────────────────────────────────────────────

@test "personal-machine: skips cleanly on enterprise machine (IS_ENTERPRISE=true)" {
  IS_ENTERPRISE="true"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  # No checks should have run
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

# ─── Global email check ────────────────────────────────────────────

@test "personal-machine.global_email: fails when global git email is unset" {
  # No .gitconfig at all
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${fail_msgs[@]}" | grep -q "global git user.email"
}

@test "personal-machine.global_email: fails when global git email is @company.example" {
  git config --file "$GIT_CONFIG_GLOBAL" user.email "fyodor@company.example"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${fail_msgs[@]}" | grep -q "global git user.email"
}

@test "personal-machine.global_email: passes when global git email is fyodor@sent.com" {
  git config --file "$GIT_CONFIG_GLOBAL" user.email "fyodor@sent.com"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${pass_msgs[@]}" | grep -q "global git user.email"
}

@test "personal-machine.global_email: passes when email is only in included ~/.gitconfig.local" {
  printf '[include]\n\tpath = ~/.gitconfig.local\n' > "$GIT_CONFIG_GLOBAL"
  git config --file "$TEST_HOME/.gitconfig.local" user.email "fyodor@sent.com"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${pass_msgs[@]}" | grep -q "global git user.email"
}

@test "personal-machine.global_email: fix writes ~/.gitconfig.local, not chezmoi-managed ~/.gitconfig" {
  printf '[include]\n\tpath = ~/.gitconfig.local\n' > "$GIT_CONFIG_GLOBAL"
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  [ "$(git config --file "$TEST_HOME/.gitconfig.local" user.email)" = "fyodor@sent.com" ]
  [ -z "$(git config --file "$GIT_CONFIG_GLOBAL" user.email || true)" ]
}

# ─── Repo-clone checks ─────────────────────────────────────────────

@test "personal-machine.dotfiles_clone: fails when ~/apps/tooling/dotfiles missing" {
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${fail_msgs[@]}" | grep -q "dotfiles"
}

@test "personal-machine.dotfiles_clone: passes when ~/apps/tooling/dotfiles is correct" {
  make_fake_repo "$TEST_HOME/apps/tooling/dotfiles" "git@github.com:fyodoriv/dotfiles.git" "feat/chezmoi"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${pass_msgs[@]}" | grep -q "fyodoriv/dotfiles"
}

@test "personal-machine.dotfiles_clone: fails when origin points at wrong URL" {
  make_fake_repo "$TEST_HOME/apps/tooling/dotfiles" "git@github.com:someone-else/dotfiles.git" "feat/chezmoi"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${fail_msgs[@]}" | grep -q "fyodoriv/dotfiles"
}

@test "personal-machine.dotfiles_clone: fails when branch is wrong" {
  make_fake_repo "$TEST_HOME/apps/tooling/dotfiles" "git@github.com:fyodoriv/dotfiles.git" "main"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${fail_msgs[@]}" | grep -q "fyodoriv/dotfiles"
}

@test "personal-machine.dotfiles_clone: passes when origin uses HTTPS form" {
  # The substring match should accept both SSH (git@github.com:...) and HTTPS
  # (https://github.com/...) clones since both are valid setup commands.
  make_fake_repo "$TEST_HOME/apps/tooling/dotfiles" "https://github.com/fyodoriv/dotfiles.git" "feat/chezmoi"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${pass_msgs[@]}" | grep -q "fyodoriv/dotfiles"
}

@test "personal-machine.agentbrew_clone: passes when ~/apps/tooling/agentbrew is correct" {
  make_fake_repo "$TEST_HOME/apps/tooling/agentbrew" "git@github.com:fyodoriv/agentbrew.git" "main"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  printf '%s\n' "${pass_msgs[@]}" | grep -q "fyodoriv/agentbrew"
}

# ─── Full happy-path ────────────────────────────────────────────────

@test "personal-machine: ALL checks pass on a correctly configured personal machine" {
  git config --file "$GIT_CONFIG_GLOBAL" user.email "fyodor@sent.com"
  make_fake_repo "$TEST_HOME/apps/tooling/dotfiles" "git@github.com:fyodoriv/dotfiles.git" "feat/chezmoi"
  make_fake_repo "$TEST_HOME/apps/tooling/agentbrew" "git@github.com:fyodoriv/agentbrew.git" "main"
  source "$TEST_DOTFILES/modules/personal-machine/doctor.sh"
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -eq 3 ]
}

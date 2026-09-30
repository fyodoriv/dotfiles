#!/usr/bin/env bats
# Tests for modules/minsky/doctor.sh — structural assertions on the
# module + functional assertions on the per-check helpers using a
# fixture minsky repo in a tmpdir.

MODULE="$BATS_TEST_DIRNAME/../modules/minsky/doctor.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_REPOS="$TEST_DIR/repos"
  TEST_REPO="$TEST_REPOS/tooling/minsky"
  TEST_SHIM="$TEST_HOME/.local/bin/minsky"
  mkdir -p "$TEST_HOME/.local/bin"
  mkdir -p "$TEST_REPO/bin" "$TEST_REPO/.minsky"
  # Make the fixture a real git repo so rev-parse works.
  # Disable global hooks (commit-msg conventional-commits gate) for the
  # fixture so the harmless "init" commit isn't rejected by the user's
  # global dotfiles hooks.
  ( cd "$TEST_REPO" && git -c init.defaultBranch=main -c core.hooksPath=/dev/null init -q && \
      git config core.hooksPath /dev/null && \
      git config user.email "t@example.com" && git config user.name "t" && \
      git commit --allow-empty -q -m "init" )
  # Fixture bin/minsky — a tiny stub that responds to --help with exit 0
  cat > "$TEST_REPO/bin/minsky" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "--help" ]; then echo "usage: minsky"; exit 0; fi
exit 1
STUB
  chmod +x "$TEST_REPO/bin/minsky"
  export HOME="$TEST_HOME"
  export DOTFILES_REPOS_DIR="$TEST_REPOS"
  export MINSKY_REPO="$TEST_REPO"
  export MINSKY_SHIM="$TEST_SHIM"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Structural ─────────────────────────────────────────────────────

@test "minsky module: exists and is executable" {
  [ -f "$MODULE" ]
  [ -x "$MODULE" ]
}

@test "minsky module: uses MINSKY_REPO env override (no hardcoded paths)" {
  grep -q 'MINSKY_REPO:-' "$MODULE"
  ! grep -q '"/Users/' "$MODULE"
}

@test "minsky module: skill-sync checks deferred to agentbrew (rule #8)" {
  # The module must NOT probe ~/.claude/skills/, ~/.cursor/skills/, etc.
  # — skill sync is agentbrew-owned per dotfiles AGENTS.md rule #8.
  # Allow the strings to appear in comments explaining the boundary,
  # but the module must contain no `check` or filesystem-probe lines
  # that target those paths.
  ! grep -E '^\s*(check|check_advisory)\s.*\.claude/skills|\.cursor/skills' "$MODULE"
  ! grep -E '\[\s+-(d|f|e)\s+["'\''$\{][^"#]*\.claude/skills' "$MODULE"
}

@test "minsky module: registers the 6 expected checks" {
  local count
  count=$(grep -cE 'check[[:space:]]+"minsky\.|check_advisory[[:space:]]+"minsky\.' "$MODULE")
  [ "$count" -ge 6 ]
}

# ── Functional: load the helpers and exercise them against fixtures ──

_load_module_helpers() {
  # Stub the dotfiles-doctor harness functions so the module can be
  # sourced without them — we only want the helper-function definitions.
  check() { :; }
  check_advisory() { :; }
  # shellcheck source=/dev/null
  source "$MODULE"
  # Export functions so they're visible inside `run`'s subshell
  export -f _minsky_repo_is_git _minsky_shim_ok _minsky_help_runs
}

@test "minsky.repo_is_git: passes on a real git checkout" {
  _load_module_helpers
  run _minsky_repo_is_git
  [ "$status" -eq 0 ]
}

@test "minsky.repo_is_git: fails on a non-git directory" {
  rm -rf "$TEST_REPO/.git"
  _load_module_helpers
  run _minsky_repo_is_git
  [ "$status" -ne 0 ]
}

@test "minsky.repo_is_git: fails when repo dir is missing" {
  rm -rf "$TEST_REPO"
  _load_module_helpers
  run _minsky_repo_is_git
  [ "$status" -ne 0 ]
}

@test "minsky.shim_ok: passes when shim symlinks to <repo>/bin/minsky" {
  ln -sf "$TEST_REPO/bin/minsky" "$TEST_SHIM"
  _load_module_helpers
  run _minsky_shim_ok
  [ "$status" -eq 0 ]
}

@test "minsky.shim_ok: fails when shim is missing" {
  _load_module_helpers
  run _minsky_shim_ok
  [ "$status" -ne 0 ]
}

@test "minsky.shim_ok: fails when shim points at the wrong target" {
  ln -sf /usr/bin/true "$TEST_SHIM"
  _load_module_helpers
  run _minsky_shim_ok
  [ "$status" -ne 0 ]
}

@test "minsky.shim_ok: passes when target ends in minsky/bin/minsky" {
  # Accept a chezmoi-managed-but-resolves-canonically target
  mkdir -p "$TEST_DIR/alt-managed/minsky/bin"
  cat > "$TEST_DIR/alt-managed/minsky/bin/minsky" <<'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$TEST_DIR/alt-managed/minsky/bin/minsky"
  ln -sf "$TEST_DIR/alt-managed/minsky/bin/minsky" "$TEST_SHIM"
  _load_module_helpers
  run _minsky_shim_ok
  [ "$status" -eq 0 ]
}

@test "minsky.help_runs: passes when shim or repo bin responds 0 to --help" {
  ln -sf "$TEST_REPO/bin/minsky" "$TEST_SHIM"
  _load_module_helpers
  run _minsky_help_runs
  [ "$status" -eq 0 ]
}

@test "minsky.help_runs: passes via repo bin/ when shim absent" {
  rm -f "$TEST_SHIM"
  _load_module_helpers
  run _minsky_help_runs
  [ "$status" -eq 0 ]
}

@test "minsky.help_runs: fails when neither shim nor repo bin is executable" {
  rm -f "$TEST_SHIM"
  rm -f "$TEST_REPO/bin/minsky"
  _load_module_helpers
  run _minsky_help_runs
  [ "$status" -ne 0 ]
}

@test "minsky.help_runs: fails when CLI exits non-zero on --help" {
  cat > "$TEST_REPO/bin/minsky" <<'STUB'
#!/bin/bash
echo "broken" >&2
exit 2
STUB
  chmod +x "$TEST_REPO/bin/minsky"
  rm -f "$TEST_SHIM"
  _load_module_helpers
  run _minsky_help_runs
  [ "$status" -ne 0 ]
}

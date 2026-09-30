#!/usr/bin/env bats
# Tests for dotfiles-doctor JSON output status accuracy under --fix mode.
#
# Bug fixed by this commit: the four `check*` helpers in bin/dotfiles-doctor
# (check, check_symlink, check_managed, check_defaults) emitted
# `_json_add "$id" "fixed" "$desc"` unconditionally after `_fix` returned,
# but `_fix` itself decides whether the fix actually worked (calls
# `fixed` on success or `fail` on failure). Result: `--json --fix` runs
# reported `"status":"fixed"` even when the fix command failed.
#
# Console counters were correct because `_fix` increments them
# directly; only the JSON output drifted from the truth.
#
# This test asserts the JSON status reflects the real `_fix` outcome by
# running a fixture module whose check fails AND whose fix command also
# fails — expected status: `fail`, not `fixed`.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export EXTRA_DOCTOR_DIR="$REPO_ROOT/tests/fixtures"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "json-fix-status: fixture module is shipped" {
  [ -f "$REPO_ROOT/tests/fixtures/json-fail-fix-module/doctor.sh" ]
  # The fixture must use `false` as BOTH the check command AND the fix command.
  # That's the precise scenario the bug surfaced on.
  grep -q '"false"' "$REPO_ROOT/tests/fixtures/json-fail-fix-module/doctor.sh"
}

@test "json-fix-status: --json --fix reports status=fail when fix command fails" {
  # Capture JSON output, then jq-parse the entry for our fixture check.
  # `|| true` because dotfiles-doctor exits 1 when any check fails;
  # we want stdout, not the exit code (bats `set -e` aborts on $? != 0).
  local out
  out="$("$REPO_ROOT/bin/dotfiles-doctor" --module json-fail-fix-module --json --fix 2>/dev/null || true)"
  # First JSON object is the fixture check (doctor emits its module first).
  # Pull its status via jq if available, else grep.
  local status
  if command -v jq >/dev/null 2>&1; then
    status="$(printf '%s' "$out" | jq -r '.[] | select(.id == "json-fail-fix-module.fix_command_always_fails") | .status')"
  else
    # Fallback string match — the JSON output uses "id":"..." then "status":"..."
    status="$(printf '%s' "$out" | grep -oE '"id":"json-fail-fix-module[^}]*"status":"[^"]+"' | grep -oE '"status":"[^"]+"$' | sed 's/"status":"\([^"]*\)"/\1/')"
  fi
  [ "$status" = "fail" ]
  # Negative assertion: definitely NOT "fixed"
  [ "$status" != "fixed" ]
}

@test "json-fix-status: --json --fix reports status=fixed when fix command succeeds" {
  # Build a fixture with a check that initially fails but a fix command
  # that ACTUALLY works. We use a tmpfile: the check tests `[ -f X ]`
  # (initially missing), the fix is `touch X`.
  local target="$TEST_DIR/fix-target"
  local green_dir="$TEST_DIR/extra/json-fix-success-module"
  mkdir -p "$green_dir"
  cat > "$green_dir/doctor.sh" <<DOCTOR
check "json-fix-success-module.fix_command_succeeds" \\
  "synthetic check fixable by touching a file" \\
  "[ -f '$target' ]" \\
  "touch '$target'"
DOCTOR
  export EXTRA_DOCTOR_DIR="$TEST_DIR/extra"
  local out
  out="$("$REPO_ROOT/bin/dotfiles-doctor" --module json-fix-success-module --json --fix 2>/dev/null)"
  local status
  if command -v jq >/dev/null 2>&1; then
    status="$(printf '%s' "$out" | jq -r '.[] | select(.id == "json-fix-success-module.fix_command_succeeds") | .status')"
  else
    status="$(printf '%s' "$out" | grep -oE '"id":"json-fix-success-module[^}]*"status":"[^"]+"' | grep -oE '"status":"[^"]+"$' | sed 's/"status":"\([^"]*\)"/\1/')"
  fi
  [ "$status" = "fixed" ]
  # Sanity: the fix actually ran and created the target file
  [ -f "$target" ]
}

@test "json-fix-status: --json (no --fix) reports status=fail with fix command in JSON" {
  # Without --fix, the check should never claim "fixed" regardless of
  # fix_cmd. Status must be "fail" + the fix command surfaces as the
  # `fix` field (so consumers know what would have been tried).
  local out
  out="$("$REPO_ROOT/bin/dotfiles-doctor" --module json-fail-fix-module --json 2>/dev/null || true)"
  local status fix
  if command -v jq >/dev/null 2>&1; then
    status="$(printf '%s' "$out" | jq -r '.[] | select(.id == "json-fail-fix-module.fix_command_always_fails") | .status')"
    fix="$(printf '%s' "$out" | jq -r '.[] | select(.id == "json-fail-fix-module.fix_command_always_fails") | .fix')"
  else
    status="$(printf '%s' "$out" | grep -oE '"id":"json-fail-fix-module[^}]*' | grep -oE '"status":"[^"]+"' | head -1 | sed 's/"status":"\([^"]*\)"/\1/')"
    fix="false"
  fi
  [ "$status" = "fail" ]
  [ "$fix" = "false" ]
}

@test "json-fix-status: check_defaults uses macOS boolean literals when fixing" {
  local domain="$TEST_DIR/defaults-bool"
  local module_dir="$TEST_DIR/extra/defaults-bool-module"
  mkdir -p "$module_dir"

  defaults write "$domain" TestBool -bool true
  cat > "$module_dir/doctor.sh" <<DOCTOR
check_defaults "defaults-bool-module.test_bool" \\
  "synthetic boolean defaults check" \\
  "$domain" TestBool "0" bool
DOCTOR

  export EXTRA_DOCTOR_DIR="$TEST_DIR/extra"
  local out
  out="$("$REPO_ROOT/bin/dotfiles-doctor" --module defaults-bool-module --json --fix 2>/dev/null)"

  local status
  if command -v jq >/dev/null 2>&1; then
    status="$(printf '%s' "$out" | jq -r '.[] | select(.id == "defaults-bool-module.test_bool") | .status')"
  else
    status="$(printf '%s' "$out" | grep -oE '"id":"defaults-bool-module[^}]*"status":"[^"]+"' | grep -oE '"status":"[^"]+"$' | sed 's/"status":"\([^"]*\)"/\1/')"
  fi
  [ "$status" = "fixed" ]
  [ "$(defaults read "$domain" TestBool)" = "0" ]
}

#!/usr/bin/env bats
# Pins the contract that EXTRA_OVERLAY_ROOT=<path> auto-discovers doctor
# modules under <path>/modules/, removing the need for callers to set
# EXTRA_DOCTOR_DIR separately. Implements user story #10 (fork dotfiles
# for your company) — section "What dotfiles does with your overlay".
#
# Status: RED today. Will pass when oss-split-implement-overlay-root
# lands. See dotfiles TASKS.md / docs/user-stories/10-fork-for-your-company.md.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_OVERLAY="$TEST_DIR/dotfiles-acme"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/modules" "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_OVERLAY/modules/acme-mod"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true

  # Reuse the existing extra-dir test fixture for the dotfiles internals
  # (lib/output.sh, lib/lock.sh, lib/stats.sh mocks + a built-in module).
  # See tests/dotfiles-doctor-extra-dir.bats for the full setup.
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/" 2>/dev/null || true

  cat > "$TEST_DOTFILES/lib/output.sh" <<'LIBEOF'
pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0
report_failures=()
pass()    { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail()    { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }
fixed()   { fix_count=$((fix_count + 1)); }
skipped() { skip_count=$((skip_count + 1)); }
audit_warn() { warn_count=$((warn_count + 1)); }
notify() { :; }
BLUE=""; GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
LIBEOF

  cat > "$TEST_DOTFILES/lib/lock.sh" <<'LOCKEOF'
acquire_lock() { return 0; }
LOCKEOF

  cat > "$TEST_DOTFILES/lib/stats.sh" <<'STATSEOF'
log_run() { :; }
STATSEOF

  mkdir -p "$TEST_DOTFILES/modules/builtin-mod"
  cat > "$TEST_DOTFILES/modules/builtin-mod/doctor.sh" <<'MODEOF'
check "builtin.one" "built-in check" "true" ""
MODEOF

  # Overlay module — must be discovered via EXTRA_OVERLAY_ROOT
  cat > "$TEST_OVERLAY/modules/acme-mod/doctor.sh" <<'MODEOF'
check "acme.mod_check" "acme overlay check" "true" ""
MODEOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "EXTRA_OVERLAY_ROOT discovers modules under <root>/modules/" {
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme.mod_check"* ]] || { echo "Expected acme.mod_check in output; got: $output"; return 1; }
  [[ "$output" == *"builtin.one"* ]] || { echo "Expected builtin.one in output (built-in module should still run); got: $output"; return 1; }
}

@test "EXTRA_OVERLAY_ROOT unset: only built-in modules discovered" {
  unset EXTRA_OVERLAY_ROOT EXTRA_DOCTOR_DIR
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" != *"acme.mod_check"* ]]
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_OVERLAY_ROOT set to missing dir: silently ignored, doctor still works" {
  EXTRA_OVERLAY_ROOT="$TEST_DIR/does-not-exist" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_OVERLAY_ROOT set with empty <root>/modules/: doctor runs cleanly" {
  rm -rf "$TEST_OVERLAY/modules"
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_OVERLAY_ROOT with colon-separated paths: rejected with clear error" {
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY:$TEST_DIR/other" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -ne 0 ]
  [[ "$output" == *"single path"* ]] || [[ "$output" == *"one overlay"* ]] || { echo "Expected error about single path requirement; got: $output"; return 1; }
}

@test "EXTRA_DOCTOR_DIR backwards-compat: still works when EXTRA_OVERLAY_ROOT unset" {
  unset EXTRA_OVERLAY_ROOT
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY/modules" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme.mod_check"* ]]
}

#!/usr/bin/env bats
# Pins the contract that EXTRA_OVERLAY_ROOT=<path> auto-discovers validate
# scripts under <path>/validate/. User story #10, sub-bullet (b) under
# "What dotfiles does with your overlay".
#
# Status: RED today. See dotfiles TASKS.md / oss-split-implement-overlay-root.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_OVERLAY="$TEST_DIR/dotfiles-acme"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/validate" "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_OVERLAY/validate"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true

  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-validate" "$TEST_DOTFILES/bin/" 2>/dev/null || true

  # Minimal lib stubs so dotfiles-validate can source its deps. Mirrors the
  # pattern in tests/dotfiles-doctor-extra-dir.bats and tests/validate.bats.
  cat > "$TEST_DOTFILES/lib/output.sh" <<'LIBEOF'
pass_count=0; fail_count=0; warn_count=0
pass()    { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail()    { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }
audit_warn() { warn_count=$((warn_count + 1)); echo "WARN: $1"; }
BLUE=""; GREEN=""; RED=""; YELLOW=""; DIM=""; NC=""
LIBEOF

  cat > "$TEST_DOTFILES/lib/secret-scan.sh" <<'SCANEOF'
# No-op stub for tests
scan_secrets() { return 0; }
SCANEOF

  # Built-in validate
  cat > "$TEST_DOTFILES/validate/builtin-check.sh" <<'BIEOF'
#!/usr/bin/env bash
echo "builtin-validate-ran"
BIEOF
  chmod +x "$TEST_DOTFILES/validate/builtin-check.sh"

  # Overlay validate — discovered via EXTRA_OVERLAY_ROOT
  cat > "$TEST_OVERLAY/validate/acme-check.sh" <<'OVEOF'
#!/usr/bin/env bash
echo "acme-validate-ran"
OVEOF
  chmod +x "$TEST_OVERLAY/validate/acme-check.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "EXTRA_OVERLAY_ROOT discovers validate scripts under <root>/validate/" {
  # Note: dotfiles-validate exits non-zero when share-gate checks fail in the
  # mocked test env (TASKS.md lint, shellcheck, etc. — unrelated to our hook).
  # We assert on overlay-script output, not exit code. The script's built-in
  # validates are hardcoded checks (hardcoded-paths, enterprise-refs, secrets,
  # script-hygiene) — not auto-discovered, so there's no "builtin-validate-ran"
  # equivalent to assert on.
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" == *"acme-validate-ran"* ]] || { echo "Expected acme-validate-ran in output; got: $output"; return 1; }
}

@test "EXTRA_OVERLAY_ROOT unset: overlay validates do not run" {
  unset EXTRA_OVERLAY_ROOT EXTRA_VALIDATE_DIR
  run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" != *"acme-validate-ran"* ]]
}

@test "EXTRA_OVERLAY_ROOT with missing <root>/validate/: gracefully ignored (no error mentioning the path)" {
  rm -rf "$TEST_OVERLAY/validate"
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" != *"acme-validate-ran"* ]]
  # Should not produce an explicit "directory not found" type error for the overlay path
  [[ "$output" != *"No such file or directory"*"$TEST_OVERLAY/validate"* ]]
}

@test "EXTRA_VALIDATE_DIR backwards-compat: still works when EXTRA_OVERLAY_ROOT unset" {
  unset EXTRA_OVERLAY_ROOT
  EXTRA_VALIDATE_DIR="$TEST_OVERLAY/validate" run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" == *"acme-validate-ran"* ]]
}

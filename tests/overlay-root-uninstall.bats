#!/usr/bin/env bats
# Pins the symmetric-uninstall contract: when EXTRA_OVERLAY_ROOT was set
# and then is unset (and `dotfiles apply` reruns), the overlay's
# contributions go away cleanly — modules, validates, brewfile entries,
# and Agentfile no longer present in dotfiles output. User story #10,
# "Symmetric uninstall" section.
#
# Status: RED today. See dotfiles TASKS.md / oss-split-implement-overlay-root.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_OVERLAY="$TEST_DIR/dotfiles-acme"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/modules" \
           "$TEST_DOTFILES/lib" "$TEST_DOTFILES/validate" \
           "$TEST_OVERLAY/modules/acme-mod" "$TEST_OVERLAY/validate"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true

  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-validate" "$TEST_DOTFILES/bin/" 2>/dev/null || true

  # Minimal lib stubs (same as overlay-root-doctor.bats)
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

  # Built-in module always present
  mkdir -p "$TEST_DOTFILES/modules/builtin-mod"
  cat > "$TEST_DOTFILES/modules/builtin-mod/doctor.sh" <<'MODEOF'
check "builtin.one" "built-in check" "true" ""
MODEOF

  # Overlay module + validate
  cat > "$TEST_OVERLAY/modules/acme-mod/doctor.sh" <<'MODEOF'
check "acme.mod_check" "acme overlay check" "true" ""
MODEOF
  cat > "$TEST_OVERLAY/validate/acme-check.sh" <<'OVEOF'
#!/usr/bin/env bash
echo "acme-validate-ran"
OVEOF
  chmod +x "$TEST_OVERLAY/validate/acme-check.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "uninstall sequence: overlay-active then overlay-unset cleans overlay output" {
  # Step 1: overlay is active — doctor sees overlay module
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [[ "$output" == *"acme.mod_check"* ]] || { echo "Expected overlay active in step 1; got: $output"; return 1; }

  # Step 2: unset overlay env var, simulating the user removing extra_overlay_root
  # from chezmoi data and running `dotfiles apply` again
  unset EXTRA_OVERLAY_ROOT
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [[ "$output" != *"acme.mod_check"* ]] || { echo "Overlay module should be gone after unset; got: $output"; return 1; }
  [[ "$output" == *"builtin.one"* ]] || { echo "Built-in module should survive uninstall; got: $output"; return 1; }
}

@test "uninstall sequence: validate scripts also disappear after unset" {
  # Step 1: overlay active
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" == *"acme-validate-ran"* ]]

  # Step 2: unset
  unset EXTRA_OVERLAY_ROOT
  run bash "$TEST_DOTFILES/bin/dotfiles-validate"
  [[ "$output" != *"acme-validate-ran"* ]]
}

@test "uninstall is idempotent: unsetting an already-unset overlay is a no-op" {
  unset EXTRA_OVERLAY_ROOT
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  # Re-running with overlay still unset
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
}

@test "user-added entries survive uninstall (no destruction of non-overlay state)" {
  # Operator adds a local module in the built-in modules dir (mimicking
  # personal customizations the operator made directly)
  mkdir -p "$TEST_DOTFILES/modules/local-mod"
  cat > "$TEST_DOTFILES/modules/local-mod/doctor.sh" <<'MODEOF'
check "local.user_mod" "operator-added module" "true" ""
MODEOF

  # Overlay was active, then unset
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  unset EXTRA_OVERLAY_ROOT
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [[ "$output" == *"local.user_mod"* ]] || { echo "User-added module should survive overlay uninstall; got: $output"; return 1; }
}

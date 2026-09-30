#!/usr/bin/env bats
# Tests for the EXTRA_DOCTOR_DIR overlay extension hook.
#
# Pins the contract that an organisation-specific overlay (e.g. a private
# repo at ~/apps/dotfiles-<org>/) can plug additional doctor modules into
# bin/dotfiles-doctor without dotfiles itself referencing the overlay path.
# The hook is the env var $EXTRA_DOCTOR_DIR (also readable from chezmoi data
# key extra_doctor_dir).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  TEST_OVERLAY="$TEST_DIR/overlay"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_DOTFILES/bin"
  mkdir -p "$TEST_DOTFILES/modules"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true

  # Minimal lib/output.sh mock
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

  # Minimal lib/lock.sh mock
  cat > "$TEST_DOTFILES/lib/lock.sh" <<'LOCKEOF'
acquire_lock() { return 0; }
LOCKEOF

  # Minimal lib/stats.sh mock
  cat > "$TEST_DOTFILES/lib/stats.sh" <<'STATSEOF'
log_run() { :; }
STATSEOF

  # One built-in module so the doctor has something to discover even when
  # no overlay is configured.
  mkdir -p "$TEST_DOTFILES/modules/builtin-mod"
  echo "cosmetic" > "$TEST_DOTFILES/modules/builtin-mod/severity"
  cat > "$TEST_DOTFILES/modules/builtin-mod/doctor.sh" <<'MODEOF'
check "builtin.one" "built-in check" "true" ""
MODEOF

  # Copy the real doctor script and patch it for isolated testing
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/dotfiles-doctor"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"|DOTFILES_DIR="'"$TEST_DOTFILES"'"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|IS_ENTERPRISE="$(chezmoi .*"|IS_ENTERPRISE="false"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|DOTFILES_PROFILE="$(chezmoi .*"|DOTFILES_PROFILE="full"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  # Resolve EXTRA_DOCTOR_DIR from the env var only (skip the chezmoi data
  # branch — the test runs in an isolated HOME without any chezmoi config).
  sed -i '' 's|^EXTRA_DOCTOR_DIR="\${EXTRA_DOCTOR_DIR:-.*"|EXTRA_DOCTOR_DIR="${EXTRA_DOCTOR_DIR:-}"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  # Disable chezmoi health checks section
  sed -i '' 's|if command -v chezmoi|if false \&\& command -v chezmoi|g' "$TEST_DOTFILES/bin/dotfiles-doctor"
  # Disable agentbrew health checks section
  sed -i '' 's|if command -v agentbrew|if false \&\& command -v agentbrew|g' "$TEST_DOTFILES/bin/dotfiles-doctor"
  # Disable stats file writing
  sed -i '' '/echo.*"task":"doctor".*>> "\$DOCTOR_TRENDS_FILE"/d' "$TEST_DOTFILES/bin/dotfiles-doctor"

  touch "$TEST_DOTFILES/.overrides"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: build an overlay dir at $TEST_OVERLAY with one module that
# registers a uniquely-named check id, and return the unique id via stdout.
_make_overlay_module() {
  local mod_name="$1"
  local check_id="$2"
  local severity="${3:-cosmetic}"
  mkdir -p "$TEST_OVERLAY/$mod_name"
  echo "$severity" > "$TEST_OVERLAY/$mod_name/severity"
  cat > "$TEST_OVERLAY/$mod_name/doctor.sh" <<MODEOF
check "$check_id" "$mod_name overlay check" "true" ""
MODEOF
}

@test "EXTRA_DOCTOR_DIR set: overlay module's check ID appears in --list" {
  _make_overlay_module "overlay-mod" "overlay.unique_check_id_12345"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [[ "$output" == *"overlay.unique_check_id_12345"* ]]
  [[ "$output" == *"overlay-mod"* ]]
}

@test "EXTRA_DOCTOR_DIR unset: overlay module's check ID does NOT appear" {
  _make_overlay_module "overlay-mod" "overlay.unique_check_id_67890"
  unset EXTRA_DOCTOR_DIR
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [[ "$output" != *"overlay.unique_check_id_67890"* ]]
  [[ "$output" != *"overlay-mod"* ]]
  # Built-in module still discovered
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_DOCTOR_DIR set to missing dir: silently ignored, doctor still works" {
  EXTRA_DOCTOR_DIR="$TEST_DIR/does-not-exist" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_DOCTOR_DIR set with empty overlay dir: doctor runs cleanly" {
  mkdir -p "$TEST_OVERLAY"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"builtin.one"* ]]
}

@test "EXTRA_DOCTOR_DIR honors per-module severity in run loop" {
  _make_overlay_module "overlay-critical" "overlay.crit_check" "critical"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity critical
  # Overlay's critical-severity module ran
  [[ "$output" == *"overlay-critical overlay check"* ]]
  # Built-in cosmetic module did NOT run (filtered out by --severity critical)
  [[ "$output" != *"built-in check"* ]]
}

@test "overlay module without severity file defaults to cosmetic" {
  mkdir -p "$TEST_OVERLAY/no-sev-mod"
  cat > "$TEST_OVERLAY/no-sev-mod/doctor.sh" <<'MODEOF'
check "overlay.no_sev" "no severity file" "true" ""
MODEOF
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity cosmetic
  [[ "$output" == *"no severity file"* ]]
}

@test "EXTRA_DOCTOR_DIR works with --module to run a single overlay module" {
  _make_overlay_module "overlay-targeted" "overlay.targeted_check"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --module overlay-targeted
  [[ "$output" == *"overlay-targeted overlay check"* ]]
  # Built-in module did NOT run (filtered out by --module overlay-targeted)
  [[ "$output" != *"built-in check"* ]]
}

@test "--module exits 1 when name not in built-ins or overlay" {
  _make_overlay_module "overlay-mod" "overlay.x"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --module nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Module not found: nonexistent"* ]]
  # Available list mentions both built-in and overlay modules
  [[ "$output" == *"builtin-mod"* ]]
  [[ "$output" == *"overlay-mod"* ]]
}

@test "--skip resolves check IDs from overlay modules" {
  _make_overlay_module "overlay-mod" "overlay.skippable"
  EXTRA_DOCTOR_DIR="$TEST_OVERLAY" run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip overlay.skippable
  [ "$status" -eq 0 ]
  grep -qx "overlay.skippable" "$TEST_DOTFILES/.overrides"
}

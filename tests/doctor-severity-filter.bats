#!/usr/bin/env bats
# Tests for dotfiles-doctor --severity filter

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_DOTFILES/bin"

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

  # Create modules with different severities
  mkdir -p "$TEST_DOTFILES/modules/mod-critical"
  echo "critical" > "$TEST_DOTFILES/modules/mod-critical/severity"
  cat > "$TEST_DOTFILES/modules/mod-critical/doctor.sh" <<'MODEOF'
check "crit.one" "critical check" "true" ""
MODEOF

  mkdir -p "$TEST_DOTFILES/modules/mod-important"
  echo "important" > "$TEST_DOTFILES/modules/mod-important/severity"
  cat > "$TEST_DOTFILES/modules/mod-important/doctor.sh" <<'MODEOF'
check "imp.one" "important check" "true" ""
MODEOF

  mkdir -p "$TEST_DOTFILES/modules/mod-performance"
  echo "performance" > "$TEST_DOTFILES/modules/mod-performance/severity"
  cat > "$TEST_DOTFILES/modules/mod-performance/doctor.sh" <<'MODEOF'
check "perf.one" "performance check" "true" ""
MODEOF

  mkdir -p "$TEST_DOTFILES/modules/mod-cosmetic"
  echo "cosmetic" > "$TEST_DOTFILES/modules/mod-cosmetic/severity"
  cat > "$TEST_DOTFILES/modules/mod-cosmetic/doctor.sh" <<'MODEOF'
check "cosm.one" "cosmetic check" "true" ""
MODEOF

  # Copy the real doctor script and patch it for isolated testing
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/dotfiles-doctor"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"|DOTFILES_DIR="'"$TEST_DOTFILES"'"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|IS_ENTERPRISE="$(chezmoi .*"|IS_ENTERPRISE="false"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|DOTFILES_PROFILE="$(chezmoi .*"|DOTFILES_PROFILE="full"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
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

@test "--severity critical runs only critical modules" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity critical
  [[ "$output" == *"critical check"* ]]
  [[ "$output" != *"important check"* ]]
  [[ "$output" != *"performance check"* ]]
  [[ "$output" != *"cosmetic check"* ]]
}

@test "--severity important runs critical + important modules" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity important
  [[ "$output" == *"critical check"* ]]
  [[ "$output" == *"important check"* ]]
  [[ "$output" != *"performance check"* ]]
  [[ "$output" != *"cosmetic check"* ]]
}

@test "--severity performance runs critical + important + performance" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity performance
  [[ "$output" == *"critical check"* ]]
  [[ "$output" == *"important check"* ]]
  [[ "$output" == *"performance check"* ]]
  [[ "$output" != *"cosmetic check"* ]]
}

@test "--severity cosmetic runs all modules (same as no filter)" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity cosmetic
  [[ "$output" == *"critical check"* ]]
  [[ "$output" == *"important check"* ]]
  [[ "$output" == *"performance check"* ]]
  [[ "$output" == *"cosmetic check"* ]]
}

@test "--severity with no value exits 1 and shows usage" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage"* ]]
}

@test "--severity with invalid level exits 1" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --severity bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"critical"* ]]
}

@test "help text documents --severity flag" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --help
  [[ "$output" == *"--severity"* ]]
}

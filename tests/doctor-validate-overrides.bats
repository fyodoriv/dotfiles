#!/usr/bin/env bats
# Tests for dotfiles-doctor --validate-overrides flag

load test_helper

DOCTOR="$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/modules/fake/"{,}
  mkdir -p "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_DOTFILES/bin"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_CI=true

  # Minimal lib/output.sh mock (counters + formatters)
  cat > "$TEST_DOTFILES/lib/output.sh" <<'LIBEOF'
pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0
report_failures=()
pass()    { pass_count=$((pass_count + 1)); }
fail()    { fail_count=$((fail_count + 1)); }
fixed()   { fix_count=$((fix_count + 1)); }
skipped() { skip_count=$((skip_count + 1)); }
audit_warn() { warn_count=$((warn_count + 1)); }
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

  # Create a fake module with known check IDs
  cat > "$TEST_DOTFILES/modules/fake/doctor.sh" <<'MODEOF'
check "fake.alpha" "Alpha check" "true" ""
check "fake.beta" "Beta check" "true" ""
MODEOF

  # Create a second module
  mkdir -p "$TEST_DOTFILES/modules/other"
  cat > "$TEST_DOTFILES/modules/other/doctor.sh" <<'MODEOF'
check "other.gamma" "Gamma check" "true" ""
MODEOF

  # Copy the real doctor script
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/dotfiles-doctor"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-doctor"

  # Override DOTFILES_DIR inside the copied script
  sed -i '' 's|DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"|DOTFILES_DIR="'"$TEST_DOTFILES"'"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  # Disable chezmoi calls
  sed -i '' 's|IS_ENTERPRISE="$(chezmoi .*"|IS_ENTERPRISE="false"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
  sed -i '' 's|DOTFILES_PROFILE="$(chezmoi .*"|DOTFILES_PROFILE="full"|' "$TEST_DOTFILES/bin/dotfiles-doctor"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "--validate-overrides passes with empty overrides file" {
  touch "$TEST_DOTFILES/.overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"All overrides are valid"* ]]
}

@test "--validate-overrides passes with valid check IDs" {
  cat > "$TEST_DOTFILES/.overrides" <<EOF
fake.alpha
other.gamma
EOF
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"All overrides are valid"* ]]
}

@test "--validate-overrides fails with unknown check ID" {
  cat > "$TEST_DOTFILES/.overrides" <<EOF
fake.alpha
typo.nonexistent
EOF
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 1 ]
  [[ "$output" == *"typo.nonexistent"* ]]
}

@test "--validate-overrides ignores comments and blank lines" {
  cat > "$TEST_DOTFILES/.overrides" <<EOF
# This is a comment
fake.alpha

# Another comment
fake.beta
EOF
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
}

@test "--validate-overrides reports multiple unknown IDs" {
  cat > "$TEST_DOTFILES/.overrides" <<EOF
fake.alpha
bad.one
bad.two
EOF
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.one"* ]]
  [[ "$output" == *"bad.two"* ]]
  [[ "$output" == *"2 unknown"* ]]
}

@test "--validate-overrides counts valid overrides" {
  cat > "$TEST_DOTFILES/.overrides" <<EOF
fake.alpha
fake.beta
other.gamma
EOF
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"3"* ]]
}

@test "--skip rejects unknown check ID without changing overrides" {
  echo "fake.alpha" > "$TEST_DOTFILES/.overrides"

  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip typo.nonexistent
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown check ID: typo.nonexistent"* ]]
  [[ "$output" == *"--list"* ]]
  [ "$(cat "$TEST_DOTFILES/.overrides")" = "fake.alpha" ]
}

@test "--skip accepts known check ID" {
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip fake.beta
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added override: fake.beta"* ]]
  grep -qx "fake.beta" "$TEST_DOTFILES/.overrides"
}

@test "--skip does not duplicate existing override" {
  echo "fake.alpha" > "$TEST_DOTFILES/.overrides"

  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip fake.alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"Override already exists: fake.alpha"* ]]
  [ "$(grep -cx "fake.alpha" "$TEST_DOTFILES/.overrides")" -eq 1 ]
}

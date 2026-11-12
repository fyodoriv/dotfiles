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

  for lib in dotfiles-source-dir dotfiles-endpoint-paths weekly-metrics; do
    cp "$BATS_TEST_DIRNAME/../lib/$lib.sh" "$TEST_DOTFILES/lib/$lib.sh"
  done

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
  cp "$BATS_TEST_DIRNAME/../lib/errors-log.sh" "$TEST_DOTFILES/lib/errors-log.sh"
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
  sed -i.bak 's|DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd)"|DOTFILES_DIR="'"$TEST_DOTFILES"'"|' "$TEST_DOTFILES/bin/dotfiles-doctor" && rm -f "$TEST_DOTFILES/bin/dotfiles-doctor.bak"
  # Disable chezmoi calls
  sed -i.bak 's|IS_ENTERPRISE="$(chezmoi .*"|IS_ENTERPRISE="false"|' "$TEST_DOTFILES/bin/dotfiles-doctor" && rm -f "$TEST_DOTFILES/bin/dotfiles-doctor.bak"
  sed -i.bak 's|DOTFILES_PROFILE="$(chezmoi .*"|DOTFILES_PROFILE="full"|' "$TEST_DOTFILES/bin/dotfiles-doctor" && rm -f "$TEST_DOTFILES/bin/dotfiles-doctor.bak"
}

teardown() {
  rm -rf "$TEST_DIR"
}

assert_doctor_succeeded() {
  local safe_status=unknown json=no failures=unknown chezmoi_failures=unknown permission=no missing=no
  [[ "$1" =~ ^[0-9]{1,3}$ ]] && safe_status="$1"
  [ "$safe_status" = 0 ] && return 0
  if printf '%s' "$2" | jq -e 'type == "array"' >/dev/null 2>&1; then
    json=yes
    failures=$(printf '%s' "$2" | jq '[.[] | objects | select(.status == "fail")] | length' 2>/dev/null) || failures=unknown
    chezmoi_failures=$(printf '%s' "$2" | jq '[.[] | objects | select(.status == "fail" and (.id | type == "string" and startswith("chezmoi.")))] | length' 2>/dev/null) || chezmoi_failures=unknown
  fi
  [[ "$2" == *'Permission denied'* ]] && permission=yes
  [[ "$2" == *'No such file or directory'* || "$2" == *'command not found'* ]] && missing=yes
  printf 'doctor status: %s; json: %s; failures: %s; chezmoi failures: %s; permission: %s; missing: %s\n' \
    "$safe_status" "$json" "$failures" "$chezmoi_failures" "$permission" "$missing" >&2
  return 1
}

install_discovery_mode_module() {
  export DOTFILES_USE_LOCAL_AI=false
  mkdir -p "$TEST_DOTFILES/modules/conditional"
  cat > "$TEST_DOTFILES/modules/conditional/doctor.sh" <<'MODEOF'
if [ "${USE_LOCAL_AI:-true}" = false ] && [ "${LIST_MODE:-false}" != true ] \
  && declare -F skipped >/dev/null; then
  skipped "conditional module is off"
  return 0
fi
check "conditional.retained" "conditional check" 'touch "$HOME/discovery-probe-ran"; false' ""
MODEOF
}

@test "discovery mode: --skip accepts an opted-out module ID" {
  install_discovery_mode_module
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip conditional.retained
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added override: conditional.retained"* ]]
  [ ! -e "$TEST_HOME/discovery-probe-ran" ]
}

@test "discovery mode: --validate-overrides accepts an opted-out module ID" {
  install_discovery_mode_module
  printf 'conditional.retained\n' > "$TEST_DOTFILES/.overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 0 ]
  [[ "$output" == *"All overrides are valid"* ]]
  [ ! -e "$TEST_HOME/discovery-probe-ran" ]
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

@test "--skip writes the per-machine file, not the tracked .overrides" {
  echo "fake.alpha" > "$TEST_DOTFILES/.overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip fake.beta
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added override: fake.beta"* ]]
  grep -qx "fake.beta" "$TEST_HOME/.config/dotfiles/overrides"
  [ "$(cat "$TEST_DOTFILES/.overrides")" = "fake.alpha" ]
}

@test "--skip does not duplicate an override from the per-machine file" {
  mkdir -p "$TEST_HOME/.config/dotfiles"
  echo "fake.beta" > "$TEST_HOME/.config/dotfiles/overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip fake.beta
  [ "$status" -eq 0 ]
  [[ "$output" == *"Override already exists: fake.beta"* ]]
  [ "$(grep -cx "fake.beta" "$TEST_HOME/.config/dotfiles/overrides")" -eq 1 ]
}

@test "--validate-overrides also checks the per-machine file" {
  touch "$TEST_DOTFILES/.overrides"
  mkdir -p "$TEST_HOME/.config/dotfiles"
  echo "typo.local" > "$TEST_HOME/.config/dotfiles/overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --validate-overrides
  [ "$status" -eq 1 ]
  [[ "$output" == *"typo.local"* ]]
}

@test "doctor failure diagnostic hides a real fixture's private output" {
  export DOTFILES_LOCAL_OVERRIDES="$TEST_DIR/absent-overrides"
  printf 'check "fake.alpha" "PRIVATE_CANARY_123" "false" ""\n' > "$TEST_DOTFILES/modules/fake/doctor.sh"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --module fake --json
  local doctor_status="$status" doctor_output="$output"
  [ "$doctor_status" -ne 0 ]
  [[ "$doctor_output" == *PRIVATE_CANARY_123* ]]
  run assert_doctor_succeeded "$doctor_status" "$doctor_output"
  [ "$status" -eq 1 ]
  [[ "$output" == *'doctor status: '* ]]
  [[ "$output" == *'json: yes'* ]]
  [[ "$output" != *PRIVATE_CANARY_123* ]]
}

@test "doctor failure diagnostic reports only allowlisted error classes" {
  run assert_doctor_succeeded 7 'PRIVATE_CANARY_123 Permission denied No such file or directory'
  [ "$status" -eq 1 ]
  [[ "$output" == *'json: no'*'permission: yes'*'missing: yes'* ]]
  [[ "$output" != *PRIVATE_CANARY_123* ]]
}

@test "doctor failure diagnostic counts a synthetic chezmoi failure" {
  export MOCK_CHEZMOI_LOG="$TEST_DIR/chezmoi-calls"
  export PATH="$TEST_DOTFILES/bin:$PATH"
  cat > "$TEST_DOTFILES/bin/chezmoi" <<'MOCK'
#!/bin/bash
case "$1" in
  doctor) printf 'doctor\n' >> "$MOCK_CHEZMOI_LOG"; printf 'error synthetic synthetic\n' ;;
  *) exit 1 ;;
esac
MOCK
  chmod +x "$TEST_DOTFILES/bin/chezmoi"
  mkdir -p "$TEST_HOME/.config/dotfiles"
  printf 'fake.alpha\n' > "$TEST_HOME/.config/dotfiles/overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --module fake --json
  local doctor_status="$status" doctor_output="$output"
  [ "$doctor_status" -ne 0 ]
  grep -qx doctor "$MOCK_CHEZMOI_LOG"
  run assert_doctor_succeeded "$doctor_status" "$doctor_output"
  [ "$status" -eq 1 ]
  [[ "$output" == *'chezmoi failures: 1'* ]]
}

@test "a per-machine override skips its check in a doctor run" {
  touch "$TEST_DOTFILES/.overrides"
  mkdir -p "$TEST_HOME/.config/dotfiles"
  echo "fake.alpha" > "$TEST_HOME/.config/dotfiles/overrides"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --module fake --json
  assert_doctor_succeeded "$status" "$output"
  [ "$(printf '%s' "$output" | jq -r '.[] | select(.id == "fake.alpha") | .status')" = skip ]
}

@test "--skip does not duplicate existing override" {
  echo "fake.alpha" > "$TEST_DOTFILES/.overrides"

  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip fake.alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"Override already exists: fake.alpha"* ]]
  [ "$(grep -cx "fake.alpha" "$TEST_DOTFILES/.overrides")" -eq 1 ]
}

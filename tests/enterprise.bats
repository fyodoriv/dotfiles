#!/usr/bin/env bats
# Tests for dotfiles-enterprise — show/toggle enterprise mode

ENTERPRISE_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-enterprise"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$TEST_HOME/.config/chezmoi" "$STUB_DIR"
  export HOME="$TEST_HOME"

  # Stub chezmoi so 'enterprise on/off' doesn't actually apply
  cat > "$STUB_DIR/chezmoi" << 'STUB'
#!/bin/bash
exit 0
STUB
  chmod +x "$STUB_DIR/chezmoi"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Static analysis ──

@test "dotfiles-enterprise exists and is executable" {
  [ -x "$ENTERPRISE_CMD" ]
}

@test "dotfiles-enterprise has correct shebang" {
  head -1 "$ENTERPRISE_CMD" | grep -q '#!/bin/bash'
}

@test "dotfiles-enterprise uses strict mode" {
  grep -q 'set -euo pipefail' "$ENTERPRISE_CMD"
}

# ── Display mode ──

@test "--help shows usage and exits 0" {
  run bash "$ENTERPRISE_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"enterprise"* ]]
}

@test "no args with missing config shows not-found message" {
  rm -f "$TEST_HOME/.config/chezmoi/chezmoi.yaml"
  run bash "$ENTERPRISE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No chezmoi config found"* ]]
}

@test "no args shows current enterprise mode off" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: false
EOF
  run bash "$ENTERPRISE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enterprise mode: off"* ]]
}

@test "no args shows current enterprise mode on" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: true
EOF
  run bash "$ENTERPRISE_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enterprise mode: on"* ]]
}

@test "invalid action exits 1" {
  run bash "$ENTERPRISE_CMD" maybe
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be 'on' or 'off'"* ]]
}

@test "toggle with missing config exits 1" {
  rm -f "$TEST_HOME/.config/chezmoi/chezmoi.yaml"
  run bash "$ENTERPRISE_CMD" on
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# ── Functional toggle tests ──

@test "enterprise on sets is_enterprise to true in config" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: false
EOF
  run bash "$ENTERPRISE_CMD" on
  [ "$status" -eq 0 ]
  result=$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")
  [ "$result" = "true" ]
}

@test "enterprise off sets is_enterprise to false in config" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: true
EOF
  run bash "$ENTERPRISE_CMD" off
  [ "$status" -eq 0 ]
  result=$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")
  [ "$result" = "false" ]
}

@test "enterprise on preserves other data fields" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  profile: full
  is_enterprise: false
  use_ai_tools: true
  auto_upgrade: false
EOF
  run bash "$ENTERPRISE_CMD" on
  [ "$status" -eq 0 ]
  [ "$(yq '.data.profile' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "full" ]
  [ "$(yq '.data.use_ai_tools' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "true" ]
  [ "$(yq '.data.auto_upgrade' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "false" ]
  [ "$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "true" ]
}

@test "enterprise off preserves other data fields" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  profile: core
  is_enterprise: true
  use_ai_tools: false
EOF
  run bash "$ENTERPRISE_CMD" off
  [ "$status" -eq 0 ]
  [ "$(yq '.data.profile' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "core" ]
  [ "$(yq '.data.use_ai_tools' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "false" ]
  [ "$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")" = "false" ]
}

@test "enterprise on is idempotent (on when already on)" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: true
EOF
  run bash "$ENTERPRISE_CMD" on
  [ "$status" -eq 0 ]
  result=$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")
  [ "$result" = "true" ]
  [[ "$output" == *"Enterprise mode: on"* ]]
}

@test "enterprise off is idempotent (off when already off)" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: false
EOF
  run bash "$ENTERPRISE_CMD" off
  [ "$status" -eq 0 ]
  result=$(yq '.data.is_enterprise' "$TEST_HOME/.config/chezmoi/chezmoi.yaml")
  [ "$result" = "false" ]
  [[ "$output" == *"Enterprise mode: off"* ]]
}

@test "enterprise on prints confirmation message" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: false
EOF
  run bash "$ENTERPRISE_CMD" on
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enterprise mode: on"* ]]
  [[ "$output" == *"Done"* ]]
}

@test "enterprise off prints confirmation message" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  is_enterprise: true
EOF
  run bash "$ENTERPRISE_CMD" off
  [ "$status" -eq 0 ]
  [[ "$output" == *"Enterprise mode: off"* ]]
  [[ "$output" == *"Done"* ]]
}

# ── Dependency guard tests ──

@test "enterprise errors when yq is not installed" {
  # Use a minimal PATH that excludes yq
  run env PATH="/usr/bin:/bin" HOME="$TEST_HOME" bash "$ENTERPRISE_CMD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"yq not found"* ]]
  [[ "$output" == *"brew install yq"* ]]
}

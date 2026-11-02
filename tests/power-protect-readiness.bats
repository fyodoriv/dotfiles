#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export AMPHETAMINE_APP_PATH="$TEST_DIR/Amphetamine.app"
  export AMPHETAMINE_POWER_PROTECT_CONFIG="$TEST_DIR/admin/amphetamine_powerProtect"
  export TEST_MACHINE_ARM64=1
  SCRIPT_MARKER="$HOME/Library/Application Scripts/com.if.Amphetamine/powerProtect.scpt"
  mkdir -p "$HOME" "$AMPHETAMINE_APP_PATH" "$TEST_DIR/bin" "$(dirname "$AMPHETAMINE_POWER_PROTECT_CONFIG")"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/defaults"
  chmod +x "$TEST_DIR/bin/defaults"
  export PATH="$TEST_DIR/bin:$PATH"
  KEEP_AWAKE_TOOLS=true
  LIST_MODE=false
  PROTECT_RESULT=missing
  sysctl() { [ "$1 $2" = '-n hw.optional.arm64' ] && printf '%s\n' "$TEST_MACHINE_ARM64"; }
  check() { :; }
  audit_warn() { :; }
  check_advisory() {
    [ "$1" = resilience.amphetamine_power_protect ] || return 0
    if $LIST_MODE; then PROTECT_RESULT=listed
    elif eval "$3"; then PROTECT_RESULT=pass
    else PROTECT_RESULT=warn; fi
  }
}

teardown() { rm -rf "$TEST_DIR"; }

run_readiness() { source "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh"; }
install_markers() {
  mkdir -p "$(dirname "$SCRIPT_MARKER")"
  touch "$SCRIPT_MARKER" "$AMPHETAMINE_POWER_PROTECT_CONFIG"
}

@test "Apple Silicon with Amphetamine warns when both readiness files are missing" {
  run_readiness
  [ "$PROTECT_RESULT" = warn ]
}

@test "the user script alone is not complete readiness" {
  install_markers
  rm "$AMPHETAMINE_POWER_PROTECT_CONFIG"
  run_readiness
  [ "$PROTECT_RESULT" = warn ]
}

@test "the administrator config alone is not complete readiness" {
  install_markers
  rm "$SCRIPT_MARKER"
  run_readiness
  [ "$PROTECT_RESULT" = warn ]
}

@test "both upstream installation markers pass the presence check" {
  install_markers
  run_readiness
  [ "$PROTECT_RESULT" = pass ]
}

@test "Intel does not get a Power Protect warning" {
  TEST_MACHINE_ARM64=0
  run_readiness
  [ "$PROTECT_RESULT" = pass ]
}

@test "a machine without Amphetamine does not get a Power Protect warning" {
  rmdir "$AMPHETAMINE_APP_PATH"
  run_readiness
  [ "$PROTECT_RESULT" = pass ]
}

@test "opting out of keep-awake tools does not get a Power Protect warning" {
  KEEP_AWAKE_TOOLS=false
  run_readiness
  [ "$PROTECT_RESULT" = pass ]
}

@test "list mode exposes the readiness ID without evaluating it" {
  LIST_MODE=true
  run_readiness
  [ "$PROTECT_RESULT" = listed ]
}

#!/usr/bin/env bats
# An unaccepted Xcode CLT license makes git, python3, clang and make exit
# non-zero. The doctor must detect it and print the sudo fix, never run it.

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  export XCODE_LICENSE_PROBE="$TEST_DIR/git"
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/lib/xcode-license.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

stub_probe() { # $1 = exit code, $2 = stderr text
  printf '#!/bin/bash\necho "%s" >&2\nexit %s\n' "$2" "$1" > "$XCODE_LICENSE_PROBE"
  chmod +x "$XCODE_LICENSE_PROBE"
}

@test "license accepted: probe succeeds, check passes" {
  stub_probe 0 "git version 2.39.5"
  run dotfiles_xcode_license_accepted
  [ "$status" -eq 0 ]
}

@test "license unaccepted: probe prints the license error, check fails" {
  stub_probe 69 "You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license' from within a Terminal window."
  run dotfiles_xcode_license_accepted
  [ "$status" -ne 0 ]
}

@test "probe fails for an unrelated reason: check passes (not a license problem)" {
  stub_probe 1 "fatal: something else"
  run dotfiles_xcode_license_accepted
  [ "$status" -eq 0 ]
}

@test "probe binary missing: check passes" {
  rm -f "$XCODE_LICENSE_PROBE"
  run dotfiles_xcode_license_accepted
  [ "$status" -eq 0 ]
}

@test "git module registers the check with the sudo fix in the message and no fix command" {
  run grep -A4 'git.xcode_license' "$DOTFILES_DIR/modules/git/doctor.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo xcodebuild -license accept"* ]]
  # Fourth argument (fix command) must be empty: doctor --fix must never run sudo.
  [[ "$output" == *'""'* ]]
}

@test "doctor lists the check id under the git module" {
  run "$DOTFILES_DIR/bin/dotfiles-doctor" --module git --list
  [[ "$output" == *"git.xcode_license"* ]]
}

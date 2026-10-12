#!/bin/bash
# Detect an unaccepted Xcode Command Line Tools license.
#
# While the license is unaccepted, every CLT-backed binary (git, python3,
# clang, make) exits non-zero and prints "You have not agreed to the Xcode
# license agreements". Accepting needs sudo and human agreement, so the
# doctor only reports it.
#
# XCODE_LICENSE_PROBE overrides the probed binary (tests use a stub).

# Returns 0 when the license is fine or the probe cannot tell; 1 only when
# the probe fails AND its output names the Xcode license.
dotfiles_xcode_license_accepted() {
  local probe="${XCODE_LICENSE_PROBE:-/usr/bin/git}" out
  [ -x "$probe" ] || return 0
  out="$("$probe" --version 2>&1)" && return 0
  case "$out" in
    *"Xcode license"*) return 1 ;;
  esac
  return 0
}

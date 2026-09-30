#!/usr/bin/env bats

# Pin invariants of bin/local-ai-readiness-check
# This file tests the static properties of the readiness-check wrapper.
# It ensures the wrapper is executable, has the correct shebang, and uses set -uo pipefail.
# These tests verify the wrapper's basic structure and safety settings.

@test "readiness-check: wrapper exists, is executable" {
  [ -x bin/local-ai-readiness-check ]
}

@test "readiness-check: has correct shebang" {
  head -1 bin/local-ai-readiness-check | grep -E '^#!/bin/bash$'
}

@test "readiness-check: declares set -uo pipefail" {
  grep -E 'set -uo pipefail' bin/local-ai-readiness-check
}
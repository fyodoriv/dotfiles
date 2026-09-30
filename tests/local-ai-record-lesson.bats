#!/usr/bin/env bats

# Pin invariants of bin/local-ai-record-lesson
# This file tests the basic structure and properties of the record-lesson script.

@test "record-lesson: wrapper exists, is executable" {
  [ -x bin/local-ai-record-lesson ]
}

@test "record-lesson: has correct shebang" {
  head -1 bin/local-ai-record-lesson | grep -q '^#!/bin/bash$'
}

@test "record-lesson: declares set -euo pipefail" {
  grep -q 'set -euo pipefail' bin/local-ai-record-lesson
}
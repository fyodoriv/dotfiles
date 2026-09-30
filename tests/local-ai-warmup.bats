#!/usr/bin/env bats

# Pin invariants of bin/local-ai-warmup
# These tests ensure the warmup script maintains its expected structure and behavior.

@test "warmup: wrapper exists, is executable" {
  [ -x bin/local-ai-warmup ]
}

@test "warmup: has correct shebang" {
  head -1 bin/local-ai-warmup | grep -q '^#!/bin/bash$'
}

@test "warmup: declares `set -uo pipefail`" {
  grep -q 'set -uo pipefail' bin/local-ai-warmup
}

@test "warmup: --help exits 0" {
  run bin/local-ai-warmup --help
  [ "$status" -eq 0 ]
}

@test "warmup: health check never spawns blocked publishers or models" {
  ! grep -vE '^[[:space:]]*#' bin/local-ai-warmup | grep -qE '(^|[[:space:]])curl([[:space:]]|$)'
  grep -q '/usr/bin/nc' bin/local-ai-warmup
  ! grep -qE 'api/generate|chat/completions|ollama run|ollama serve|lms.*(load|server start)' bin/local-ai-warmup
  grep -q 'model generation disabled' bin/local-ai-warmup
}
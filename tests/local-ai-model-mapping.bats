#!/usr/bin/env bats
# Tests for the Ollama model-id mapping in modules/local-ai/doctor.sh.
#
# Regression: before this fix both files substituted `qwen3:${SIZE_BUCKET}`
# unconditionally, so a 64GB box produced the invalid tag
# `qwen3:coder-30b`. The correct Ollama library name is `qwen3-coder:30b`
# (a separate entry from the vanilla `qwen3` family).

load test_helper

DOCTOR="$BATS_TEST_DIRNAME/../modules/local-ai/doctor.sh"

@test "doctor: coder-30b bucket maps to qwen3-coder:30b" {
  grep -q 'coder-30b)' "$DOCTOR"
  grep -q '"qwen3-coder:30b"' "$DOCTOR"
}

@test "doctor: no naive qwen3:coder-30b substitution remains in code" {
  ! grep -vE '^\s*#' "$DOCTOR" | grep -q 'qwen3:coder-30b'
}

@test "health checker contains no model mapping or generation endpoint" {
  local warmup="$BATS_TEST_DIRNAME/../bin/local-ai-warmup"
  ! grep -qE 'OLLAMA_PRIMARY|qwen3-coder|api/generate' "$warmup"
}

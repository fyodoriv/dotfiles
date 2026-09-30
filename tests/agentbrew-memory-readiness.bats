#!/usr/bin/env bats
# Tests for the doctor-process shared AgentBrew memory readiness result.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_BIN="$TEST_DIR/bin"
  AGENTBREW_LOG="$TEST_DIR/agentbrew.log"

  mkdir -p "$TEST_BIN"
  : > "$AGENTBREW_LOG"
  cat > "$TEST_BIN/agentbrew" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$AGENTBREW_LOG"
exit "${MOCK_AGENTBREW_STATUS:-0}"
EOF
  chmod +x "$TEST_BIN/agentbrew"

  export AGENTBREW_LOG
  export PATH="$TEST_BIN:$PATH"
  source "$BATS_TEST_DIRNAME/../lib/agentbrew-memory-readiness.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

agentbrew_call_count() {
  wc -l < "$AGENTBREW_LOG" | tr -d ' '
}

@test "reuses a successful memory readiness result within one doctor process" {
  dotfiles_agentbrew_memory_doctor_ready
  dotfiles_agentbrew_memory_doctor_ready

  [ "$(agentbrew_call_count)" -eq 1 ]
  [ "$(cat "$AGENTBREW_LOG")" = "memory doctor --ready" ]
}

@test "reuses a failing memory readiness result within one doctor process" {
  export MOCK_AGENTBREW_STATUS=7

  if dotfiles_agentbrew_memory_doctor_ready; then
    false
  fi
  if dotfiles_agentbrew_memory_doctor_ready; then
    false
  fi

  [ "$(agentbrew_call_count)" -eq 1 ]
}

@test "AgentBrew and Cursor doctors use the shared readiness helper" {
  grep -Fq 'source "$DOTFILES_DIR/lib/agentbrew-memory-readiness.sh"' \
    "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  grep -Fq 'dotfiles_agentbrew_memory_doctor_ready' \
    "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  grep -Fq 'source "$DOTFILES_DIR/lib/agentbrew-memory-readiness.sh"' \
    "$BATS_TEST_DIRNAME/../modules/cursor/doctor.sh"
  grep -Fq 'dotfiles_agentbrew_memory_doctor_ready' \
    "$BATS_TEST_DIRNAME/../modules/cursor/doctor.sh"
}

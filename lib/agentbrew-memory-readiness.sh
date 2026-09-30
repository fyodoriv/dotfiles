#!/bin/bash
# Process-scoped single-flight for AgentBrew's complete memory readiness gate.
#
# Both the AgentBrew and Cursor doctor modules need the same expensive MCP
# discovery check. A doctor invocation sources modules into one Bash process,
# so retain its result only for that process. The next doctor run always
# performs a fresh readiness check.

dotfiles_agentbrew_memory_doctor_ready() {
  if [ "${DOTFILES_DOCTOR_MEMORY_READY_PROCESS_HAS_RESULT:-0}" = "1" ]; then
    return "${DOTFILES_DOCTOR_MEMORY_READY_PROCESS_STATUS:-1}"
  fi

  local status=0
  agentbrew memory doctor --ready >/dev/null 2>&1 || status=$?

  DOTFILES_DOCTOR_MEMORY_READY_PROCESS_HAS_RESULT=1
  DOTFILES_DOCTOR_MEMORY_READY_PROCESS_STATUS="$status"
  return "$status"
}

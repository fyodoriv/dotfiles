#!/bin/bash
# Memory doctor checks — lifecycle owned by AgentBrew (agentbrew memory *).

if ! command -v agentbrew >/dev/null 2>&1; then
  check "memory.agentbrew_available" \
    "agentbrew CLI available for memory lifecycle" \
    "false" \
    "install tooling/agentbrew and run: agentbrew memory enable"
  return 0
fi

memory_enabled() {
  agentbrew memory status --json 2>/dev/null | jq -e '.enabled == true' >/dev/null 2>&1
}

check_advisory "memory.agentbrew_doctor" \
  "shared memory MCP discovery, daemon, and behavioral bootstrap healthy" \
  "agentbrew memory doctor >/dev/null 2>&1" \
  "agentbrew memory fix"

if memory_enabled; then
  check_advisory "memory.project_sync_advisory" \
    "Claude project-memory metadata is fresh (advisory; global recall stays available)" \
    "agentbrew memory sync-projects --check >/dev/null 2>&1" \
    "dotfiles-memory-sync-projects"

  check_advisory "memory.transport_compatibility" \
    "shared-memory transport compatibility evidence is available for staged security hardening" \
    "agentbrew memory transport-report >/dev/null 2>&1" \
    "agentbrew memory fix; then agentbrew memory transport-report --json"
fi

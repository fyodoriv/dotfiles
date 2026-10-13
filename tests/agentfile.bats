#!/usr/bin/env bats

agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

# The 2026-10-13 usage audit removed context7, tasks-mcp, github, figma,
# chrome-devtools, and shadcn-mcp (0 calls in 180 days). playwright stays.
@test "Agentfile includes MCP servers expected in fresh agent sessions" {
  for server in playwright; do
    run awk -v server="$server" '
      /^mcp:/ { in_mcp = 1; next }
      /^[^[:space:]][^:]*:/ { in_mcp = 0 }
      in_mcp && $0 ~ "^[[:space:]]+- " server "$" { found = 1 }
      in_mcp && $0 ~ "^[[:space:]]+- name: " server "$" { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$agentfile"
    [ "$status" -eq 0 ]
  done
}

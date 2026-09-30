#!/usr/bin/env bats

agentfile="$BATS_TEST_DIRNAME/../Agentfile.yaml"

@test "Agentfile includes MCP servers expected in fresh Devin sessions" {
  for server in context7 playwright tasks-mcp github; do
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

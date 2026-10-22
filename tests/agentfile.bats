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

# Parse a YAML file the way a broken Agentfile would fail agentbrew: yq when
# it is on PATH (the Brewfile installs it), else the macOS system Ruby.
parse_yaml() {
  if command -v yq >/dev/null 2>&1; then
    yq e '.' "$1" >/dev/null
  elif [ -x /usr/bin/ruby ]; then
    /usr/bin/ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$1"
  else
    echo "no YAML parser (install yq)" >&2
    return 2
  fi
}

@test "Agentfile.yaml parses as YAML" {
  run parse_yaml "$agentfile"
  [ "$status" -ne 2 ] || skip "needs yq or ruby"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "the Agentfile YAML check fails on a broken file" {
  printf 'skills:\n  - a\n bad: [\n' > "$BATS_TEST_TMPDIR/broken.yaml"
  run parse_yaml "$BATS_TEST_TMPDIR/broken.yaml"
  [ "$status" -ne 2 ] || skip "needs yq or ruby"
  [ "$status" -ne 0 ]
}

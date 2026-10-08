#!/usr/bin/env bats
# Functional tests for modules/agentbrew/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.config/agentbrew"
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/agentbrew-memory-readiness.sh" \
    "$TEST_DOTFILES/lib/agentbrew-memory-readiness.sh"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0
  warn_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  audit_warn() { warn_count=$((warn_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    else
      audit_warn "$desc"
    fi
  }

  # Mock agentbrew as available
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/bash' > "$TEST_DIR/bin/agentbrew"
  chmod +x "$TEST_DIR/bin/agentbrew"
  export PATH="$TEST_DIR/bin:$PATH"

  # These tests focus on the 4 original file/CLI checks. The env-var and
  # npm-leftover checks added later are orthogonal — override them out of
  # these tests so the pass/fail counts stay meaningful.
  cat >> "$OVERRIDES_FILE" << EOF
agentbrew.env_github_token
agentbrew.env_slack_bot_token
agentbrew.env_slack_user_token
agentbrew.env_jira_url
agentbrew.env_jira_username
agentbrew.env_jira_api_token
agentbrew.env_jenkins_url
agentbrew.env_jenkins_user
agentbrew.env_jenkins_api_token
agentbrew.claude_no_npm_leftover
agentbrew.mcp_servers_ready
agentbrew.global_agentfile_in_sync
agentbrew.hooks_enforcing
agentbrew.memory_service_singleton
agentbrew.memory_launchagent_identity
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "agentbrew: passes when all files and CLI exist" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$pass_count" -eq 4 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: fails when Agentfile.yaml and state missing" {
  rm -f "$TEST_HOME/.config/agentbrew/state.yaml"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -ge 2 ]
}

@test "agentbrew: fails when no executable is on PATH" {
  rm -f "$TEST_DIR/bin/agentbrew"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "agentbrew: overrides skip checks" {
  echo "agentbrew.cli_available" >> "$OVERRIDES_FILE"
  echo "agentbrew.agentfile_exists" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$skip_count" -ge 2 ]
}

@test "agentbrew: global Agentfile without .yaml extension passes" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  # Use Agentfile without .yaml extension
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$pass_count" -eq 4 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: Jenkins env checks only run when Jenkins MCP is registered" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: context7
    command: npx
    args: []
    env: {}
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  sed -i.bak '/agentbrew.env_jenkins_/d' "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: Jira env checks only run when atlassian MCP is registered" {
  unset JIRA_URL JIRA_USERNAME JIRA_API_TOKEN
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: context7
    command: npx
    args: []
    env: {}
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  sed -i.bak '/agentbrew.env_jira_/d' "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: Jira env checks fail when atlassian MCP is registered without env" {
  unset JIRA_URL JIRA_USERNAME JIRA_API_TOKEN
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: atlassian
    command: uvx
    args: []
    env:
      JIRA_URL: \${JIRA_URL}
      JIRA_USERNAME: \${JIRA_USERNAME}
      JIRA_API_TOKEN: \${JIRA_API_TOKEN}
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  sed -i.bak '/agentbrew.env_jira_/d' "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -eq 3 ]
}

@test "agentbrew: Jenkins env checks fail when Jenkins MCP is registered without env" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: jenkins
    command: npx
    args: []
    env:
      JENKINS_URL: \${JENKINS_URL}
      JENKINS_USER: \${JENKINS_USER}
      JENKINS_API_TOKEN: \${JENKINS_API_TOKEN}
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  sed -i.bak '/agentbrew.env_jenkins_/d' "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$fail_count" -eq 3 ]
}

@test "agentbrew: state missing but Agentfile present fails only initialized check" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  rm -f "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$pass_count" -ge 2 ]
  [ "$fail_count" -ge 1 ]
}

@test "agentbrew: global Agentfile drift check fails when canonical merge differs" {
  grep -v '^agentbrew.global_agentfile_in_sync$' "$OVERRIDES_FILE" > "$OVERRIDES_FILE.tmp"
  mv "$OVERRIDES_FILE.tmp" "$OVERRIDES_FILE"

  mkdir -p "$TEST_DIR/dotfiles-acme"
  export EXTRA_OVERLAY_ROOT="$TEST_DIR/dotfiles-acme"
  echo "mcp: [context7]" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "mcp: [acme-internal-mcp]" > "$EXTRA_OVERLAY_ROOT/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: [stale]" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ]; then
  if [ "$3" = "--help" ]; then
    echo "Usage: agentbrew agentfile merge [options] <agentfiles...>"
    exit 0
  fi
  output=""
  previous=""
  for arg in "$@"; do
    if [ "$previous" = "--output" ]; then
      output="$arg"
      break
    fi
    previous="$arg"
  done
  echo "mcp: [context7, acme-internal-mcp]" > "$output"
fi
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 1 ]
}

@test "agentbrew: global Agentfile drift check passes when canonical merge matches" {
  grep -v '^agentbrew.global_agentfile_in_sync$' "$OVERRIDES_FILE" > "$OVERRIDES_FILE.tmp"
  mv "$OVERRIDES_FILE.tmp" "$OVERRIDES_FILE"

  echo "mcp: [context7]" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: [context7]" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ]; then
  if [ "$3" = "--help" ]; then
    echo "Usage: agentbrew agentfile merge [options] <agentfiles...>"
    exit 0
  fi
  output=""
  previous=""
  for arg in "$@"; do
    if [ "$previous" = "--output" ]; then
      output="$arg"
      break
    fi
    previous="$arg"
  done
  echo "mcp: [context7]" > "$output"
fi
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -ge 1 ]
}

@test "agentbrew: global Agentfile drift check includes the no-Cursor Agentfile when use_cursor=false" {
  grep -v '^agentbrew.global_agentfile_in_sync$' "$OVERRIDES_FILE" > "$OVERRIDES_FILE.tmp"
  mv "$OVERRIDES_FILE.tmp" "$OVERRIDES_FILE"

  echo "mcp: [context7]" > "$TEST_DOTFILES/Agentfile.yaml"
  mkdir -p "$TEST_DOTFILES/config"
  printf 'excludeAgents:\n  - cursor\n' > "$TEST_DOTFILES/config/agentfile-no-cursor.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  # The sync script merged both inputs; the mock merge records their names.
  echo "Agentfile.yaml agentfile-no-cursor.yaml" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ]; then
  if [ "$3" = "--help" ]; then
    echo "Usage: agentbrew agentfile merge [options] <agentfiles...>"
    exit 0
  fi
  shift 2
  inputs=()
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--output" ]; then output="$2"; shift 2; continue; fi
    inputs+=("$(basename "$1")")
    shift
  done
  echo "${inputs[*]}" > "$output"
fi
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  DOTFILES_USE_CURSOR=false source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -ge 1 ]
}

@test "agentbrew: global Agentfile drift check skips when CLI lacks agentfile merge" {
  grep -v '^agentbrew.global_agentfile_in_sync$' "$OVERRIDES_FILE" > "$OVERRIDES_FILE.tmp"
  mv "$OVERRIDES_FILE.tmp" "$OVERRIDES_FILE"

  mkdir -p "$TEST_DIR/dotfiles-acme"
  export EXTRA_OVERLAY_ROOT="$TEST_DIR/dotfiles-acme"
  echo "mcp: [context7]" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "mcp: [acme-internal-mcp]" > "$EXTRA_OVERLAY_ROOT/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: [stale]" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
if [ "$1" = "agentfile" ] && [ "$2" = "merge" ] && [ "$3" = "--help" ]; then
  echo "Usage: agentbrew [options] [command]"
fi
exit 0
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory daemon check skips when AI tools are disabled" {
  chezmoi() { echo "false"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory daemon check skips when MCP is not registered" {
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: context7
    command: npx
    args: []
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory daemon warns when registered but endpoint is unavailable" {
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << 'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory daemon passes the full MCP discovery probe" {
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << 'EOF'
#!/bin/bash
if [ "$*" = "memory doctor --ready" ]; then
  exit 0
fi
exit 0
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -eq 5 ]
}

@test "agentbrew: memory daemon warns when the full discovery gate returns empty or unhealthy" {
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << 'EOF'
#!/bin/bash
[ "$*" = "memory doctor --ready" ] && exit 1
exit 0
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory LaunchAgent identity passes for the canonical path and HOME" {
  sed -i.bak '/agentbrew.memory_launchagent_identity/d' "$OVERRIDES_FILE"
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << EOF
#!/bin/bash
case "\$*" in
  "memory doctor --ready") exit 0 ;;
  "memory status --json")
    printf '%s\n' '{"launchAgentIdentity":{"loaded":true,"path":"'"$TEST_HOME"'/Library/LaunchAgents/com.agentbrew.mcp-memory.plist","home":"'"$TEST_HOME"'","canonical":true}}'
    ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory LaunchAgent identity fails for a temporary HOME job" {
  sed -i.bak '/agentbrew.memory_launchagent_identity/d' "$OVERRIDES_FILE"
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << 'EOF'
#!/bin/bash
case "$*" in
  "memory doctor --ready") exit 0 ;;
  "memory status --json")
    printf '%s\n' '{"launchAgentIdentity":{"loaded":true,"path":"/tmp/home/Library/LaunchAgents/com.agentbrew.mcp-memory.plist","home":"/tmp/home","canonical":false}}'
    ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -ge 1 ]
}

@test "agentbrew: memory singleton check passes with one server process" {
  sed -i.bak '/agentbrew.memory_service_singleton/d' "$OVERRIDES_FILE"
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DIR/bin/ps" << 'EOF'
#!/bin/bash
echo "/tmp/python /tmp/memory server --streamable-http --sse-port 18765"
EOF
  chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/ps"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: memory singleton check warns on a duplicate stdio server" {
  sed -i.bak '/agentbrew.memory_service_singleton/d' "$OVERRIDES_FILE"
  chezmoi() { echo "true"; }
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  cat > "$TEST_HOME/.config/agentbrew/state.yaml" << EOF
mcpServers:
  - name: memory
    url: http://127.0.0.1:18765/mcp
EOF
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/curl" << 'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$TEST_DIR/bin/ps" << 'EOF'
#!/bin/bash
echo "/tmp/python /tmp/memory server --streamable-http --sse-port 18765"
echo "/tmp/python /tmp/memory server"
EOF
  chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/ps"
  PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$warn_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

# ── Generic mcp_servers_ready check ─────────────────────

@test "agentbrew: mcp_servers_ready passes when agentbrew status reports zero env-vars drift" {
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  # Mock agentbrew status --json to return zero drift
  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
case "$1 $2" in
  "status --json")
    echo '{"agents":45,"mcpServers":5,"drift":[]}'
    ;;
  *) ;;
esac
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  # Run only this one check
  sed -i.bak '/agentbrew.mcp_servers_ready/d' "$OVERRIDES_FILE"
  for c in cli_available agentfile_exists initialized global_agentfile; do
    echo "agentbrew.$c" >> "$OVERRIDES_FILE"
  done

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -ge 1 ]
}

@test "agentbrew: mcp_servers_ready fails when agentbrew reports mcp-env-vars drift (regression)" {
  # Regression: pre-fix, jira-mcp got silently filtered out for Devin because
  # JIRA_EMAIL only lived in macOS Keychain (not env). agentbrew sync still
  # succeeded, but invoking jira-mcp from Devin returned
  # "Server 'jira-mcp' not found in configuration". This check is the
  # user-facing safety net: the doctor MUST fail when agentbrew status
  # reports any mcp-env-vars drift, regardless of which underlying
  # filter/fallback was wrong.
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
case "$1 $2" in
  "status --json")
    echo '{"agents":45,"mcpServers":5,"drift":[{"agent":"jira-mcp","type":"mcp-env-vars","detail":"missing env vars: JIRA_EMAIL — Run: agentbrew setup"}]}'
    ;;
  *) ;;
esac
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  sed -i.bak '/agentbrew.mcp_servers_ready/d' "$OVERRIDES_FILE"
  for c in cli_available agentfile_exists initialized global_agentfile; do
    echo "agentbrew.$c" >> "$OVERRIDES_FILE"
  done

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  [ "$fail_count" -ge 1 ]
}

@test "agentbrew: mcp_servers_ready does not double-fail when agentbrew CLI is missing" {
  # If `agentbrew` isn't on PATH, the existing `agentbrew.cli_available`
  # check already fails — `mcp_servers_ready` should silently return clean
  # (return 0) so we don't surface the same problem twice.
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  rm -f "$TEST_DIR/bin/agentbrew"

  sed -i.bak '/agentbrew.mcp_servers_ready/d' "$OVERRIDES_FILE"
  for c in cli_available agentfile_exists initialized global_agentfile; do
    echo "agentbrew.$c" >> "$OVERRIDES_FILE"
  done

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  # Only the cli_available was overridden, so the new check should not be
  # registered at all (the `if command -v agentbrew` guard skips it).
  # Net effect: zero fails from mcp_servers_ready specifically.
  [ "$fail_count" -eq 0 ]
}

@test "agentbrew: mcp_servers_ready tolerates broken agentbrew status output gracefully" {
  # If agentbrew status outputs non-JSON (e.g., transient crash, version
  # skew), the check should NOT fail with a confusing error — it should
  # treat the situation as "we don't know" and pass cleanly, leaving
  # other checks (cli_available) to surface the underlying problem.
  echo "mcp: []" > "$TEST_DOTFILES/Agentfile.yaml"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"

  cat > "$TEST_DIR/bin/agentbrew" << 'AGENTBREW_EOF'
#!/bin/bash
case "$1 $2" in
  "status --json")
    echo "Error: not initialized"
    exit 1
    ;;
  *) ;;
esac
AGENTBREW_EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  sed -i.bak '/agentbrew.mcp_servers_ready/d' "$OVERRIDES_FILE"
  for c in cli_available agentfile_exists initialized global_agentfile; do
    echo "agentbrew.$c" >> "$OVERRIDES_FILE"
  done

  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"

  # Broken status output → check returns clean → no new fail
  [ "$fail_count" -eq 0 ]
}

# ── agentbrew.hooks_enforcing — Phase-1 hook observation recurring gate ──
# These un-skip the check (setup overrides it for the count-based tests) and
# stub the located agentbrew checkout's scripts/hook-observation.sh.

_unskip_hooks_enforcing() {
  grep -v '^agentbrew.hooks_enforcing$' "$OVERRIDES_FILE" > "$OVERRIDES_FILE.tmp"
  mv "$OVERRIDES_FILE.tmp" "$OVERRIDES_FILE"
}

_stub_observation_script() { # $1 = exit code the fake script returns
  local fake_ab="$TEST_DIR/agentbrew"
  mkdir -p "$fake_ab/scripts" "$TEST_DOTFILES/lib"
  printf '#!/bin/bash\nexit %s\n' "$1" > "$fake_ab/scripts/hook-observation.sh"
  chmod +x "$fake_ab/scripts/hook-observation.sh"
  printf 'agentbrew_locate() { printf "%%s" "%s"; }\n' "$fake_ab" \
    > "$TEST_DOTFILES/lib/agentbrew-locate.sh"
}

@test "agentbrew: hooks_enforcing warns on a ran-no-enforce hook" {
  _unskip_hooks_enforcing
  _stub_observation_script 1   # script exit 1 = ran-no-enforce
  mkdir -p "$TEST_HOME/.cache/agentbrew"
  echo '{}' > "$TEST_HOME/.cache/agentbrew/hook-decisions.jsonl"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$warn_count" -ge 1 ]
}

@test "agentbrew: hooks_enforcing passes when all hooks enforce" {
  _unskip_hooks_enforcing
  _stub_observation_script 0   # script exit 0 = all enforced / clean
  mkdir -p "$TEST_HOME/.cache/agentbrew"
  echo '{}' > "$TEST_HOME/.cache/agentbrew/hook-decisions.jsonl"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$warn_count" -eq 0 ]
}

@test "agentbrew: hooks_enforcing skips cleanly when no decision log exists" {
  _unskip_hooks_enforcing
  _stub_observation_script 1   # would warn IF the log existed
  rm -f "$TEST_HOME/.cache/agentbrew/hook-decisions.jsonl"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$warn_count" -eq 0 ]
}

@test "agentbrew: hooks_enforcing skips when agentbrew checkout not found" {
  _unskip_hooks_enforcing
  # No lib/agentbrew-locate.sh in TEST_DOTFILES → helper returns 0 (skip)
  mkdir -p "$TEST_HOME/.cache/agentbrew"
  echo '{}' > "$TEST_HOME/.cache/agentbrew/hook-decisions.jsonl"
  source "$BATS_TEST_DIRNAME/../modules/agentbrew/doctor.sh"
  [ "$warn_count" -eq 0 ]
}

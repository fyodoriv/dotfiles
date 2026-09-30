#!/usr/bin/env bats
# Tests for bin/dotfiles-reload-launchagents — ship-it Step 13 LaunchAgent reload.

RELOAD_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-reload-launchagents"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$STUB_DIR"

  cat > "$STUB_DIR/launchctl" << STUB
#!/bin/bash
echo "launchctl \$*" >> "$TEST_DIR/launchctl.log"
exit 0
STUB
  chmod +x "$STUB_DIR/launchctl"

  cat > "$STUB_DIR/pkill" << STUB
#!/bin/bash
echo "pkill \$*" >> "$TEST_DIR/pkill.log"
exit 0
STUB
  chmod +x "$STUB_DIR/pkill"

  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  cat > "$STUB_DIR/chezmoi" <<STUB
#!/bin/bash
[ "\${1:-}" = "source-path" ] && printf '%s\n' "$REPO_ROOT"
STUB
  chmod +x "$STUB_DIR/chezmoi"

  export PATH="$STUB_DIR:$PATH"
  export ORIG_HOME="$HOME"
  export HOME="$TEST_HOME"
}

teardown() {
  export HOME="$ORIG_HOME"
  rm -rf "$TEST_DIR"
}

_deploy_core_plists() {
  local label
  for label in \
    com.dotfiles.gui-path \
    com.dotfiles.network-resilience \
    com.dotfiles.heal-stuck-agents \
    com.dotfiles.agent-keepawake \
    com.dotfiles.cursor-at-login \
    com.dotfiles.dotfiles-doctor \
    com.dotfiles.chrome-profile \
    com.dotfiles.agent-browser-chrome \
    com.dotfiles.debug-chrome \
    com.dotfiles.tooling-chrome; do
    printf '%s\n' '<?xml version="1.0"?><plist/>' > "$TEST_HOME/Library/LaunchAgents/${label}.plist"
  done
}

@test "dotfiles-reload-launchagents exists and is executable" {
  [ -x "$RELOAD_CMD" ]
}

@test "dotfiles-reload-launchagents has bash shebang and strict mode" {
  head -1 "$RELOAD_CMD" | grep -q '#!/bin/bash'
  grep -q 'set -o errexit' "$RELOAD_CMD"
}

@test "--help shows usage and exits 0" {
  run bash "$RELOAD_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-reload-launchagents"* ]]
  [[ "$output" == *"--kickstart"* ]]
  [[ "$output" == *"--kill-chrome"* ]]
}

@test "development checkout reload is report-only" {
  cat > "$STUB_DIR/chezmoi" <<STUB
#!/bin/bash
[ "\${1:-}" = "source-path" ] && printf '%s\n' "$TEST_DIR/development"
STUB
  chmod +x "$STUB_DIR/chezmoi"
  _deploy_core_plists

  run bash "$RELOAD_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"report-only outside the applied checkout"* ]]
  [ ! -f "$TEST_DIR/launchctl.log" ]
}

@test "bootstrap mode bootouts and bootstraps all core LaunchAgents" {
  _deploy_core_plists

  run bash "$RELOAD_CMD"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/launchctl.log" ]
  grep -c 'bootout' "$TEST_DIR/launchctl.log" | grep -q '^10$'
  grep -c 'bootstrap' "$TEST_DIR/launchctl.log" | grep -q '^10$'
  grep -q 'com.dotfiles.heal-stuck-agents' "$TEST_DIR/launchctl.log"
  grep -q 'com.dotfiles.gui-path' "$TEST_DIR/launchctl.log"
  grep -q 'com.dotfiles.agent-keepawake' "$TEST_DIR/launchctl.log"
  grep -q 'com.dotfiles.chrome-profile' "$TEST_DIR/launchctl.log"
  grep -q 'com.dotfiles.tooling-chrome' "$TEST_DIR/launchctl.log"
}

@test "dotfiles-reload-launchagents no longer manages dotfiles mcp-memory agents" {
  ! grep -q 'com.dotfiles.mcp-memory' "$RELOAD_CMD"
}

@test "kickstart mode uses kickstart -k instead of bootstrap" {
  _deploy_core_plists

  run bash "$RELOAD_CMD" --kickstart
  [ "$status" -eq 0 ]

  grep -q 'kickstart -k' "$TEST_DIR/launchctl.log"
  ! grep -q 'bootstrap' "$TEST_DIR/launchctl.log"
}

@test "--kill-chrome invokes pkill before bootstrap" {
  _deploy_core_plists

  run bash "$RELOAD_CMD" --kill-chrome
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/pkill.log" ]
  grep -q 'remote-debugging-port=922' "$TEST_DIR/pkill.log"
}

@test "CDP Chrome bootstrap failure auto-retries with port-specific pkill" {
  _deploy_core_plists

  cat > "$STUB_DIR/launchctl" << STUB
#!/bin/bash
echo "launchctl \$*" >> "$TEST_DIR/launchctl.log"
if [[ "\$1" == bootstrap* ]] && [[ "\$3" == *agent-browser-chrome.plist ]]; then
  if ! grep -q 'agent-browser-chrome-retry' "$TEST_DIR/launchctl.log" 2>/dev/null; then
    echo "agent-browser-chrome-retry" >> "$TEST_DIR/launchctl.log"
    exit 1
  fi
fi
exit 0
STUB
  chmod +x "$STUB_DIR/launchctl"

  run bash "$RELOAD_CMD"
  [ "$status" -eq 0 ]

  grep -q 'remote-debugging-port=9223' "$TEST_DIR/pkill.log"
  grep -c 'bootstrap' "$TEST_DIR/launchctl.log" | grep -q '^1[0-9]$'
}

@test "dry-run prints actions without calling launchctl" {
  _deploy_core_plists

  run bash "$RELOAD_CMD" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run]"* ]]
  [ ! -f "$TEST_DIR/launchctl.log" ]
}

@test "missing plist is skipped with warning" {
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.gui-path.plist"

  run bash "$RELOAD_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
  grep -q 'com.dotfiles.gui-path' "$TEST_DIR/launchctl.log"
  ! grep -q 'com.dotfiles.tooling-chrome' "$TEST_DIR/launchctl.log" || true
}

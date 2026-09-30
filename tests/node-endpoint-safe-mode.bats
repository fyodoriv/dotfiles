#!/usr/bin/env bats

setup() {
  export TEST_HOME="$BATS_TEST_TMPDIR/home"
  export FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  export LAUNCHCTL_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  mkdir -p "$TEST_HOME/Library/LaunchAgents" "$FAKE_BIN"

  cat >"$FAKE_BIN/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF
  cat >"$FAKE_BIN/node" <<EOF
#!/bin/bash
touch "$BATS_TEST_TMPDIR/node-executed"
exit 99
EOF
  cat >"$FAKE_BIN/codesign" <<'EOF'
#!/bin/bash
cat >&2 <<'SIG'
Authority=Developer ID Application: Node.js Foundation (HX7739G8FX)
TeamIdentifier=HX7739G8FX
SIG
EOF
  cat >"$FAKE_BIN/launchctl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$LAUNCHCTL_LOG"
exit 0
EOF
  chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/node" "$FAKE_BIN/codesign" "$FAKE_BIN/launchctl"
}

@test "blocked Node helper preserves the uvx memory daemon and disables Node jobs" {
  touch \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist" \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.competitor-watch.plist" \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.mcp-memory.plist" \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.mcp-memory-maintain.plist" \
    "$TEST_HOME/Library/LaunchAgents/com.dotfiles.dotfiles-upgrade.plist"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 3 unattended agentbrew job(s)"* ]]
  [ -f "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ]
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
  ! grep -q 'com.agentbrew.mcp-memory$' "$LAUNCHCTL_LOG"
  grep -q 'disable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
  grep -q 'bootout gui/.*/com.agentbrew.competitor-watch' "$LAUNCHCTL_LOG"
  grep -q 'disable gui/.*/com.agentbrew.mcp-memory-maintain' "$LAUNCHCTL_LOG"
  grep -q 'disable gui/.*/com.dotfiles.dotfiles-upgrade' "$LAUNCHCTL_LOG"
  grep -q 'bootout gui/.*/com.dotfiles.dotfiles-upgrade' "$LAUNCHCTL_LOG"
}

@test "apply-time agentbrew sync exits before blocked Node executes" {
  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 CHEZMOI_SOURCE_DIR="$PWD" \
    bash .chezmoiscripts/run_after_agentbrew-sync.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"agentbrew sync skipped"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
}

@test "doctor gates Node-dependent modules behind explicit exception opt-in" {
  grep -q 'DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER' bin/dotfiles-doctor
  grep -q 'agentbrew|agentbrew-\*|resilience' bin/dotfiles-doctor
  grep -q '_agentbrew_runtime_allowed' bin/dotfiles-doctor
  grep -q 'Node.js Foundation publisher is blocked' bin/dotfiles-doctor
}

@test "standalone doctor health footer does not execute blocked agentbrew runtime" {
  cat >"$FAKE_BIN/agentbrew" <<EOF
#!/bin/bash
touch "$BATS_TEST_TMPDIR/agentbrew-executed"
exit 99
EOF
  cat >"$FAKE_BIN/chezmoi" <<'EOF'
#!/bin/bash
case "$1" in
  execute-template) echo true ;;
  doctor) exit 0 ;;
esac
EOF
  chmod +x "$FAKE_BIN/agentbrew" "$FAKE_BIN/chezmoi"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    bin/dotfiles-doctor --module agentbrew

  [ "$status" -eq 0 ]
  [[ "$output" == *"agentbrew skipped: Node.js Foundation publisher is blocked"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
  [ ! -e "$BATS_TEST_TMPDIR/agentbrew-executed" ]
}

@test "security doctor verifies recurring Node safe mode and unloaded jobs" {
  grep -q 'security.recurring_automation_no_blocked_node' modules/security/doctor.sh
  grep -q 'security.blocked_node_jobs_unloaded' modules/security/doctor.sh
  grep -q 'security.node_publisher_exception' modules/security/doctor.sh
  grep -q 'com.agentbrew.mcp-memory' modules/security/doctor.sh
}

@test "TASKS pre-commit lint never spawns blocked Node" {
  grep -q 'TeamIdentifier=HX7739G8FX' git-hooks/pre-commit
  grep -q 'TASKS.md npx lint deferred to CI' git-hooks/pre-commit
}

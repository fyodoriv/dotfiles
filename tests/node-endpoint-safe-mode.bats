#!/usr/bin/env bats

setup() {
  # The dotfiles BASH_ENV hook prepends real shim dirs, and DOTFILES_REPOS_DIR
  # points the agentbrew shim at a real checkout. Keep tests hermetic.
  unset BASH_ENV ENV DOTFILES_REPOS_DIR
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
# fake-publisher: node-foundation
touch "$BATS_TEST_TMPDIR/node-executed"
exit 99
EOF
  # Binaries marked node-foundation report the blocked Team ID; others report
  # a different publisher.
  cat >"$FAKE_BIN/codesign" <<'EOF'
#!/bin/bash
target="${*: -1}"
if grep -q 'fake-publisher: node-foundation' "$target" 2>/dev/null; then
  cat >&2 <<'SIG'
Authority=Developer ID Application: Node.js Foundation (HX7739G8FX)
TeamIdentifier=HX7739G8FX
SIG
else
  cat >&2 <<'SIG'
Authority=Developer ID Application: Example Packager (EXAMPLE123)
TeamIdentifier=EXAMPLE123
SIG
fi
EOF
  export AGENT_NODE_DIR="$BATS_TEST_TMPDIR/agent-node/bin"
  mkdir -p "$AGENT_NODE_DIR"
  cat >"$AGENT_NODE_DIR/node" <<EOF
#!/bin/bash
touch "$BATS_TEST_TMPDIR/agent-node-executed"
exit 0
EOF
  chmod +x "$AGENT_NODE_DIR/node"
  cat >"$FAKE_BIN/launchctl" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>"$LAUNCHCTL_LOG"
exit 0
EOF
  chmod +x "$FAKE_BIN/uname" "$FAKE_BIN/node" "$FAKE_BIN/codesign" "$FAKE_BIN/launchctl"
}

# Write a LaunchAgent plist whose program and PATH are given.
write_job() {
  local label="$1" program="$2" job_path="$3"
  cat >"$TEST_HOME/Library/LaunchAgents/$label.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array><string>$program</string><string>cli.js</string></array>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>$job_path</string></dict>
</dict></plist>
EOF
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

@test "agent Node opt-in keeps agentbrew jobs on that Node and still stops Topgrade" {
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$AGENT_NODE_DIR:/usr/bin:/bin"
  touch "$TEST_HOME/Library/LaunchAgents/com.dotfiles.dotfiles-upgrade.plist"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 DOTFILES_AGENT_NODE_BIN="$AGENT_NODE_DIR/node" \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 0 unattended agentbrew job(s)"* ]]
  [[ "$output" == *"approved agent Node $AGENT_NODE_DIR/node"* ]]
  [ -f "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ]
  ! grep -q 'disable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
  grep -q 'enable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
  grep -q 'disable gui/.*/com.dotfiles.dotfiles-upgrade' "$LAUNCHCTL_LOG"
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
}

@test "agent Node opt-in still disables a job whose program is the blocked Node" {
  write_job com.agentbrew.check "$FAKE_BIN/node" "$AGENT_NODE_DIR:/usr/bin:/bin"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 DOTFILES_AGENT_NODE_BIN="$AGENT_NODE_DIR/node" \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 1 unattended agentbrew job(s)"* ]]
  grep -q 'disable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
}

@test "agent Node signed by the blocked publisher is ignored" {
  write_job com.agentbrew.check "$FAKE_BIN/node" "$FAKE_BIN:/usr/bin:/bin"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 DOTFILES_AGENT_NODE_BIN="$FAKE_BIN/node" \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 1 unattended agentbrew job(s)"* ]]
  [[ "$output" != *"approved agent Node"* ]]
}

@test "missing agent Node path is ignored" {
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$AGENT_NODE_DIR:/usr/bin:/bin"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 DOTFILES_AGENT_NODE_BIN="$BATS_TEST_TMPDIR/missing/node" \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 1 unattended agentbrew job(s)"* ]]
  grep -q 'disable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
}

@test "apply-time agentbrew sync runs on the approved agent Node" {
  cat >"$FAKE_BIN/agentbrew" <<EOF
#!/bin/bash
command -v node >>"$BATS_TEST_TMPDIR/agentbrew-node"
exit 0
EOF
  chmod +x "$FAKE_BIN/agentbrew"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 CHEZMOI_SOURCE_DIR="$PWD" \
    DOTFILES_AGENT_NODE_BIN="$AGENT_NODE_DIR/node" \
    bash .chezmoiscripts/run_after_agentbrew-sync.sh

  [ "$status" -eq 0 ]
  [[ "$output" != *"agentbrew sync skipped"* ]]
  [[ "$output" == *"agentbrew sync uses approved agent Node"* ]]
  [ "$(sort -u "$BATS_TEST_TMPDIR/agentbrew-node")" = "$AGENT_NODE_DIR/node" ]
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
}

@test "doctor runs the agentbrew module and footer on the approved agent Node" {
  cat >"$FAKE_BIN/agentbrew" <<EOF
#!/bin/bash
command -v node >>"$BATS_TEST_TMPDIR/agentbrew-node"
exit 0
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
    DOTFILES_AGENT_NODE_BIN="$AGENT_NODE_DIR/node" \
    bin/dotfiles-doctor --module agentbrew

  [[ "$output" != *"skipped: Node.js Foundation publisher is blocked"* ]]
  [ -s "$BATS_TEST_TMPDIR/agentbrew-node" ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/agentbrew-node")" = "$AGENT_NODE_DIR/node" ]
  [ ! -e "$BATS_TEST_TMPDIR/node-executed" ]
}

@test "launchagent check flags a job whose program is the blocked Node" {
  source lib/dotfiles-agent-node.sh
  write_job com.agentbrew.check "$FAKE_BIN/node" "/usr/bin:/bin"
  PATH="$FAKE_BIN:$PATH" dotfiles_launchagent_runs_blocked_node \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist"
}

@test "launchagent check passes a job that runs only the approved Node" {
  source lib/dotfiles-agent-node.sh
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$AGENT_NODE_DIR:/usr/bin:/bin"
  ! PATH="$FAKE_BIN:$PATH" dotfiles_launchagent_runs_blocked_node \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist"
}

@test "security doctor only requires blocked-Node jobs to be unloaded" {
  grep -q 'dotfiles_launchagent_runs_blocked_node' modules/security/doctor.sh
  grep -q 'dotfiles_agent_node_bin' modules/security/doctor.sh
}

@test "launchagent check passes a job whose blocked fnm bin follows the approved Node" {
  source lib/dotfiles-agent-node.sh
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$AGENT_NODE_DIR:$FAKE_BIN:/usr/bin:/bin"
  ! PATH="$FAKE_BIN:$PATH" dotfiles_launchagent_runs_blocked_node \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist"
}

@test "launchagent check flags a job whose first node on PATH is the blocked one" {
  source lib/dotfiles-agent-node.sh
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$FAKE_BIN:$AGENT_NODE_DIR:/usr/bin:/bin"
  PATH="$FAKE_BIN:$PATH" dotfiles_launchagent_runs_blocked_node \
    "$TEST_HOME/Library/LaunchAgents/com.agentbrew.check.plist"
}

@test "agent Node opt-in keeps a job whose blocked fnm bin follows the approved Node" {
  write_job com.agentbrew.check "$AGENT_NODE_DIR/node" "$AGENT_NODE_DIR:$FAKE_BIN:/usr/bin:/bin"

  run env HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_MANAGED_ENDPOINT=1 DOTFILES_AGENT_NODE_BIN="$AGENT_NODE_DIR/node" \
    bin/dotfiles-disable-blocked-node-automation

  [ "$status" -eq 0 ]
  [[ "$output" == *"Disabled 0 unattended agentbrew job(s)"* ]]
  ! grep -q 'disable gui/.*/com.agentbrew.check' "$LAUNCHCTL_LOG"
}

# Source the security module with check helpers that only record check ids.
security_check_ids() {
  env -i HOME="$TEST_HOME" PATH="$FAKE_BIN:/usr/bin:/bin" \
    DOTFILES_DIR="$PWD" DOTFILES_MODULE_DIR="$PWD" "$@" \
    /bin/bash -c '
      check() { echo "$1"; }
      check_advisory() { echo "$1"; }
      check_symlink() { echo "$1"; }
      check_managed() { echo "$1"; }
      pass() { :; }; fail() { :; }; fixed() { :; }; skipped() { :; }; audit_warn() { :; }
      is_overridden() { return 1; }
      FIX_MODE=false; LIST_MODE=false; QUIET_MODE=true
      source modules/security/doctor.sh
    ' 2>/dev/null
}

@test "unmanaged Mac with official Node does not require Node jobs unloaded" {
  run security_check_ids
  [[ "$output" != *"security.blocked_node_jobs_unloaded"* ]]
}

@test "managed endpoint with official Node requires Node jobs unloaded" {
  run security_check_ids DOTFILES_MANAGED_ENDPOINT=1
  [[ "$output" == *"security.blocked_node_jobs_unloaded"* ]]
}

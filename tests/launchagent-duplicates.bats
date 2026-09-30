#!/usr/bin/env bats
# Tests for lib/launchagent-duplicates.sh — one LaunchAgent per job.

setup() {
  TEST_DIR="$(mktemp -d)"
  AGENTS="$TEST_DIR/LaunchAgents"
  DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$AGENTS" "$DOTFILES/bin" "$TEST_DIR/stub"
  # launchctl must never touch the real session from a test.
  printf '#!/bin/bash\necho "$*" >> "%s/launchctl.log"\n' "$TEST_DIR" > "$TEST_DIR/stub/launchctl"
  chmod +x "$TEST_DIR/stub/launchctl"
  export PATH="$TEST_DIR/stub:$PATH"
  # shellcheck source=../lib/launchagent-duplicates.sh
  source "$BATS_TEST_DIRNAME/../lib/launchagent-duplicates.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# make_agent <label> <arg>... — write an XML plist with ProgramArguments.
make_agent() {
  local label="$1"; shift
  local args="" a
  for a in "$@"; do args+="<string>$a</string>"; done
  cat > "$AGENTS/$label.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>$args</array>
<key>EnvironmentVariables</key><dict><key>PATH</key><string>$DOTFILES/bin:/usr/bin</string></dict>
</dict></plist>
PLIST
}

@test "an agent with the same command as a managed agent is a duplicate" {
  make_agent com.dotfiles.opencode-serve /opt/opencode serve --port 4096
  make_agent com.legacy.opencode-serve /opt/opencode serve --port 4096

  run launchagent_duplicates "$AGENTS" "$DOTFILES"

  [ "$status" -eq 0 ]
  [ "$output" = "com.legacy.opencode-serve" ]
}

@test "an agent that runs a dotfiles script is a duplicate" {
  make_agent com.tooling.sync "$DOTFILES/bin/tooling-sync"

  run launchagent_duplicates "$AGENTS" "$DOTFILES"

  [ "$output" = "com.tooling.sync" ]
}

@test "unrelated agents and managed agents are never duplicates" {
  make_agent com.dotfiles.dotfiles-sync /bin/bash "$DOTFILES/bin/dotfiles-sync"
  make_agent com.vendor.updater /opt/vendor/updater --check
  # PATH in the environment points at dotfiles/bin; only the command counts.
  make_agent com.vendor.tool /usr/bin/true

  run launchagent_duplicates "$AGENTS" "$DOTFILES"

  [ -z "$output" ]
}

@test "a same-name agent with another command is only a suffix twin" {
  make_agent com.dotfiles.gui-path /bin/bash -c 'launchctl setenv PATH /new'
  make_agent com.legacy.gui-path /bin/bash -c 'launchctl setenv PATH /old'

  run launchagent_duplicates "$AGENTS" "$DOTFILES"
  [ -z "$output" ]

  run launchagent_suffix_twins "$AGENTS"
  [ "$output" = "com.legacy.gui-path com.dotfiles.gui-path" ]
}

@test "remove_duplicates unloads and deletes duplicates and their backups only" {
  make_agent com.dotfiles.git-maintain /bin/bash "$DOTFILES/bin/git-maintain"
  make_agent com.legacy.git-maintain /bin/bash "$DOTFILES/bin/git-maintain"
  touch "$AGENTS/com.legacy.git-maintain.plist.backup.20260101"
  make_agent com.vendor.updater /opt/vendor/updater

  run launchagent_remove_duplicates "$AGENTS" "$DOTFILES"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Unloading duplicate: com.legacy.git-maintain"* ]]
  [ ! -e "$AGENTS/com.legacy.git-maintain.plist" ]
  [ ! -e "$AGENTS/com.legacy.git-maintain.plist.backup.20260101" ]
  [ -e "$AGENTS/com.dotfiles.git-maintain.plist" ]
  [ -e "$AGENTS/com.vendor.updater.plist" ]
  grep -q "unload $AGENTS/com.legacy.git-maintain.plist" "$TEST_DIR/launchctl.log"
}

@test "duplicate detection survives set -e and agents without a command" {
  # The lifecycle script runs with `set -euo pipefail`. A third-party plist
  # with neither ProgramArguments nor Program must not abort the scan.
  make_agent com.dotfiles.git-maintain /bin/bash "$DOTFILES/bin/git-maintain"
  make_agent com.legacy.git-maintain /bin/bash "$DOTFILES/bin/git-maintain"
  cat > "$AGENTS/com.vendor.nocommand.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>Label</key><string>com.vendor.nocommand</string></dict></plist>
PLIST

  run bash -c 'set -euo pipefail; source "$1"; launchagent_duplicates "$2" "$3"' _ \
    "$BATS_TEST_DIRNAME/../lib/launchagent-duplicates.sh" "$AGENTS" "$DOTFILES"

  [ "$status" -eq 0 ]
  [ "$output" = "com.legacy.git-maintain" ]
}

@test "renamed debug Chrome cleanup removes other <prefix>-debug-chrome agents" {
  make_agent com.dotfiles.debug-chrome /bin/bash "$DOTFILES/bin/debug-chrome"
  make_agent com.dotfiles.old-debug-chrome /bin/bash "$DOTFILES/bin/old-debug-chrome"
  touch "$AGENTS/com.dotfiles.old-debug-chrome.plist.backup.20260101"

  run launchagent_remove_renamed_debug_chrome "$AGENTS"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Unloading renamed debug Chrome agent: com.dotfiles.old-debug-chrome"* ]]
  [ ! -e "$AGENTS/com.dotfiles.old-debug-chrome.plist" ]
  [ ! -e "$AGENTS/com.dotfiles.old-debug-chrome.plist.backup.20260101" ]
  [ -e "$AGENTS/com.dotfiles.debug-chrome.plist" ]
  grep -q "unload $AGENTS/com.dotfiles.old-debug-chrome.plist" "$TEST_DIR/launchctl.log"
  ! grep -q "com.dotfiles.debug-chrome.plist" "$TEST_DIR/launchctl.log"
}

@test "renamed debug Chrome cleanup is a no-op when nothing matches" {
  make_agent com.dotfiles.debug-chrome /bin/bash "$DOTFILES/bin/debug-chrome"
  make_agent com.dotfiles.tooling-chrome /bin/bash "$DOTFILES/bin/tooling-chrome"

  run launchagent_remove_renamed_debug_chrome "$AGENTS"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -e "$AGENTS/com.dotfiles.debug-chrome.plist" ]
  [ -e "$AGENTS/com.dotfiles.tooling-chrome.plist" ]
}

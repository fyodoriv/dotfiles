#!/usr/bin/env bats
# Tests for the sleep/wake → network-watchdog integration.
#
# `home/sleep` and `home/wakeup` are symlinked to `~/.sleep` and `~/.wakeup`
# (via the chezmoi symlink mode) and invoked by the sleepwatcher LaunchAgent
# (`launchagents/com.dotfiles.sleepwatcher.plist.tmpl`). `~/.wakeup` is
# expected to kick `bin/network-watchdog` after resume so agent sessions
# come back to a healthy network. A typo in the plist or a rename of the
# scripts would silently break resume-time network recovery — these tests
# pin the glue so it fails loudly in CI instead.
#
# Closes test-sleepwatcher-hooks.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
SLEEP="$REPO_ROOT/home/sleep"
WAKEUP="$REPO_ROOT/home/wakeup"
PLIST="$REPO_ROOT/launchagents/com.dotfiles.sleepwatcher.plist.tmpl"
WATCHDOG="$REPO_ROOT/bin/network-watchdog"

@test "home/sleep exists and is executable" {
  [ -x "$SLEEP" ]
}

@test "home/wakeup exists and is executable" {
  [ -x "$WAKEUP" ]
}

@test "home/sleep has correct shebang" {
  head -1 "$SLEEP" | grep -q '#!/bin/bash'
}

@test "home/wakeup has correct shebang" {
  head -1 "$WAKEUP" | grep -q '#!/bin/bash'
}

@test "home/wakeup calls network-watchdog" {
  grep -q 'network-watchdog' "$WAKEUP"
}

@test "home/wakeup invokes network-watchdog with --quiet" {
  grep -q 'network-watchdog.*--quiet' "$WAKEUP"
}

@test "home/wakeup runs network-watchdog in the background" {
  # Sleepwatcher blocks on ~/.wakeup; the watchdog must be backgrounded
  # so wake completes promptly. Look for a trailing & on the watchdog line.
  grep -E 'network-watchdog.*&\s*$' "$WAKEUP" >/dev/null
}

@test "home/wakeup runs dotfiles-agent-wake-recover in the background" {
  grep -E 'dotfiles-agent-wake-recover --quiet &' "$WAKEUP" >/dev/null
}

@test "home/wakeup does not hardcode apps/dotfiles path" {
  # `dotfiles_dir` is a chezmoi prompt with default `apps/dotfiles`, but
  # adopters can choose another path. The plist already puts
  # `{{ .dotfiles_dir }}/bin` on PATH, so `home/wakeup` must call
  # `network-watchdog` by name (not by an absolute `apps/dotfiles` path)
  # to stay portable. A regression to the hardcoded form would silently
  # break wake-time recovery for any adopter on a non-default path.
  if grep -F 'apps/dotfiles' "$WAKEUP"; then
    echo "home/wakeup reintroduced a hardcoded apps/dotfiles path"
    echo "fix: call 'network-watchdog --quiet &' — the sleepwatcher plist puts it on PATH"
    return 1
  fi
}

@test "home/wakeup invokes network-watchdog via PATH" {
  # Look for a bare `network-watchdog ...` invocation (no absolute or
  # tilde-rooted path). Comments and HOME-anchored references must not
  # prefix the executable.
  grep -E '^[[:space:]]*network-watchdog[[:space:]]' "$WAKEUP" >/dev/null || {
    echo "home/wakeup must invoke network-watchdog by name (no absolute path)"
    return 1
  }
}

@test "bin/network-watchdog exists and is executable (target of home/wakeup)" {
  [ -x "$WATCHDOG" ]
}

@test "sleepwatcher plist exists" {
  [ -f "$PLIST" ]
}

@test "sleepwatcher plist references ~/.sleep" {
  grep -q '\.sleep' "$PLIST"
}

@test "sleepwatcher plist references ~/.wakeup" {
  grep -q '\.wakeup' "$PLIST"
}

@test "sleepwatcher plist passes -s flag (sleep script)" {
  # Format: <string>-s</string><string>...path/.sleep</string>
  grep -A1 '<string>-s</string>' "$PLIST" | grep -q '\.sleep'
}

@test "sleepwatcher plist passes -w flag (wake script)" {
  grep -A1 '<string>-w</string>' "$PLIST" | grep -q '\.wakeup'
}

@test "sleepwatcher plist Label matches the file basename" {
  # com.dotfiles.sleepwatcher.plist.tmpl → Label: com.dotfiles.sleepwatcher
  grep -A1 '<key>Label</key>' "$PLIST" | grep -q 'com.dotfiles.sleepwatcher'
}

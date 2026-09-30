#!/usr/bin/env bats
# Tests for setup-chrome script

load test_helper

CHROME_CMD="$BATS_TEST_DIRNAME/../bin/setup-chrome"

@test "setup-chrome script exists and is executable" {
  [ -f "$CHROME_CMD" ]
  [ -x "$CHROME_CMD" ]
}

@test "setup-chrome script has correct shebang" {
  head -1 "$CHROME_CMD" | grep -q '#!/bin/bash'
}

@test "setup-chrome script sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$CHROME_CMD"
}

@test "setup-chrome --ext shows extension recommendations" {
  run "$CHROME_CMD" --ext
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "React Developer Tools"
  echo "$output" | grep -q "JSON Formatter"
  echo "$output" | grep -q "uBlock Origin"
}

@test "setup-chrome lists at least 6 extensions" {
  run "$CHROME_CMD" --ext
  count=$(echo "$output" | grep -c 'chrome.google.com/webstore' || true)
  [ "$count" -ge 6 ]
}

@test "setup-chrome applies DevTools availability setting" {
  grep -q 'DevToolsAvailability' "$CHROME_CMD"
}

@test "setup-chrome enables full URLs in address bar" {
  grep -q 'ShowFullURLsInAddressBar' "$CHROME_CMD"
}

@test "setup-chrome disables background mode" {
  grep -q 'BackgroundModeEnabled.*false' "$CHROME_CMD"
}

@test "setup-chrome disables swipe navigation" {
  grep -q 'AppleEnableSwipeNavigateWithScrolls.*false' "$CHROME_CMD"
}

@test "setup-chrome applies performance flags via python" {
  grep -q 'enable-gpu-rasterization' "$CHROME_CMD"
  grep -q 'enable-parallel-downloading' "$CHROME_CMD"
  grep -q 'enable-zero-copy' "$CHROME_CMD"
}

@test "setup-chrome removes problematic flags" {
  grep -q 'smooth-scrolling@2' "$CHROME_CMD"
  grep -q 'enable-webrtc-hide-local-ips-with-mdns' "$CHROME_CMD"
  grep -q 'flags_remove' "$CHROME_CMD"
}

@test "setup-chrome backs up Local State before modifying flags" {
  grep -q 'LOCAL_STATE.*backup' "$CHROME_CMD"
}

@test "setup-chrome skips flags when the PERSONAL Chrome is running" {
  # Must filter out agent-browser daemons (--user-data-dir=<custom>) so the
  # background CDP Chromes don't permanently block the flag-apply pass.
  grep -q 'MacOS..Google Chrome' "$CHROME_CMD"  # awk pattern, escaped slashes
  grep -q -- '--user-data-dir=' "$CHROME_CMD"
}

@test "setup-chrome lists custom search engine shortcuts" {
  grep -q 'npmjs.com/search' "$CHROME_CMD"
  grep -q 'developer.mozilla.org' "$CHROME_CMD"
  grep -q 'github.com/search' "$CHROME_CMD"
  grep -q 'stackoverflow.com' "$CHROME_CMD"
}

@test "setup-chrome documents remote debugging CDP port" {
  grep -q 'remote-debugging-port' "$CHROME_CMD"
  grep -q '9222' "$CHROME_CMD"
}

@test "setup-chrome enforces default profile via Local State" {
  grep -q 'last_used.*work_profile' "$CHROME_CMD"
  grep -q 'last_active_profiles' "$CHROME_CMD"
  grep -q 'show_picker_on_startup.*False' "$CHROME_CMD"
}

@test "setup-chrome detects Work profile by configurable email domain" {
  grep -q 'WORK_EMAIL_DOMAIN' "$CHROME_CMD"
  grep -q 'work_email_domain' "$CHROME_CMD"
  grep -q 'user_name' "$CHROME_CMD"
}

@test "setup-chrome has python3 dependency guard" {
  grep -q 'command -v python3' "$CHROME_CMD"
  grep -q 'xcode-select --install' "$CHROME_CMD"
}

@test "chrome doctor module exists" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  [ -f "$DOCTOR" ]
}

@test "chrome doctor checks default profile" {
  DOCTOR="$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  grep -q 'chrome.default_profile' "$DOCTOR"
  grep -q 'WORK_EMAIL_DOMAIN' "$DOCTOR"
}

@test "chrome-debug launchagent plist exists" {
  PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.chrome-debug.plist.tmpl"
  [ -f "$PLIST" ]
}

@test "chrome-debug launchagent uses port 9222" {
  PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.chrome-debug.plist.tmpl"
  grep -q '9222' "$PLIST"
}

@test "chrome-debug launchagent uses separate user-data-dir" {
  PLIST="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.chrome-debug.plist.tmpl"
  grep -q 'chrome-debug' "$PLIST"
  # Must not use the default Chrome profile
  ! grep -q 'Google/Chrome"' "$PLIST"
}

@test "setup-chrome describes enterprise mode in company-neutral language" {
  # OSS-readiness regression: this script's enterprise-flag comment was
  # rewritten to drop company-specific framing. The negative case (no
  # company identifiers) is enforced by the OSS-readiness invariant in
  # tests/no-org-refs (the global allowlist gate). This test pins the
  # positive phrasing so a future "fixup" can't silently drop the
  # comment without failing here.
  grep -Fq 'enterprise-specific settings' "$CHROME_CMD"
}

#!/usr/bin/env bats
# Functional tests for modules/chrome/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export IS_ENTERPRISE=false

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  CI_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  # Mock defaults store
  MOCK_DEFAULTS="$TEST_DIR/mock_defaults"
  mkdir -p "$MOCK_DEFAULTS"

  set_default() {
    local domain="$1" key="$2" value="$3"
    mkdir -p "$MOCK_DEFAULTS/$domain"
    printf '%s' "$value" > "$MOCK_DEFAULTS/$domain/$key"
  }

  check_defaults() {
    local id="$1" desc="$2" domain="$3" key="$4" expected="$5" type="$6"
    if $LIST_MODE; then return; fi
    if $CI_MODE; then skipped "$desc (CI)"; return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    local current
    current=$(cat "$MOCK_DEFAULTS/$domain/$key" 2>/dev/null) || current=""
    if [ "$current" = "$expected" ]; then
      pass "$desc"
    elif $FIX_MODE; then
      mkdir -p "$MOCK_DEFAULTS/$domain"
      printf '%s' "$expected" > "$MOCK_DEFAULTS/$domain/$key"
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

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

  # Mock chezmoi
  chezmoi() { echo "example.com"; }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "chrome: defaults pass when values match" {
  set_default com.google.Chrome DevToolsAvailability "1"
  set_default com.google.Chrome ShowFullURLsInAddressBar "1"
  set_default com.google.Chrome AppleEnableSwipeNavigateWithScrolls "0"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  [ "$pass_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "chrome: defaults fail when values differ" {
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  [ "$fail_count" -eq 3 ]
}

@test "chrome: fix mode writes correct values" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  [ "$fix_count" -ge 3 ]
  [ "$(cat "$MOCK_DEFAULTS/com.google.Chrome/DevToolsAvailability")" = "1" ]
}

@test "chrome: enterprise gate skips work profile check when not enterprise" {
  IS_ENTERPRISE=false
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  # Only 3 check_defaults, no chrome.default_profile
  local total=$((pass_count + fail_count + fix_count + skip_count))
  [ "$total" -eq 3 ]
}

@test "chrome: overrides skip checks" {
  echo "chrome.devtools" >> "$OVERRIDES_FILE"
  echo "chrome.full_urls" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  [ "$skip_count" -ge 2 ]
}

@test "chrome: install guard skips work profile check when Chrome is missing" {
  IS_ENTERPRISE=true
  # Point CHROME_APP_DIR at a path that doesn't exist — the guard
  # should keep the work-profile check from registering.
  export CHROME_APP_DIR="$TEST_DIR/no-chrome.app"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  # Only the 3 check_defaults calls register; chrome.default_profile
  # is gated out by the install guard.
  local total=$((pass_count + fail_count + fix_count + skip_count))
  [ "$total" -eq 3 ] || {
    echo "expected 3 checks (no chrome.default_profile when Chrome is missing); got $total"
    return 1
  }
}

@test "chrome: work profile check registers when Chrome is installed and IS_ENTERPRISE=true" {
  IS_ENTERPRISE=true
  # Synthesize a fake Chrome.app dir — the guard only checks for the
  # directory, not the binary inside.
  mkdir -p "$TEST_DIR/Chrome.app"
  export CHROME_APP_DIR="$TEST_DIR/Chrome.app"
  # And a Local State file the helper can read; matching profile.
  mkdir -p "$TEST_HOME/Library/Application Support/Google/Chrome"
  cat > "$TEST_HOME/Library/Application Support/Google/Chrome/Local State" <<'JSON'
{
  "profile": {
    "last_used": "Profile 1",
    "info_cache": {
      "Profile 1": {"user_name": "alice@example.com"}
    },
    "show_picker_on_startup": false
  }
}
JSON
  set_default com.google.Chrome DevToolsAvailability "1"
  set_default com.google.Chrome ShowFullURLsInAddressBar "1"
  set_default com.google.Chrome AppleEnableSwipeNavigateWithScrolls "0"

  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  # 3 defaults + 3 work-profile checks (default_profile + chromework_router + default_browser)
  local total=$((pass_count + fail_count + fix_count + skip_count))
  [ "$total" -eq 6 ] || {
    echo "expected 6 checks when Chrome is installed; got $total"
    return 1
  }
}

@test "chrome: _chrome_default_profile_matches passes on healthy Local State" {
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  local state="$TEST_DIR/healthy-state.json"
  cat > "$state" <<'JSON'
{
  "profile": {
    "last_used": "Profile 1",
    "info_cache": {
      "Profile 1": {"user_name": "alice@example.com"}
    },
    "show_picker_on_startup": false
  }
}
JSON
  _chrome_default_profile_matches "$state" "example.com"
}

@test "chrome: _chrome_default_profile_matches fails on missing Local State file" {
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  run _chrome_default_profile_matches "$TEST_DIR/does-not-exist.json" "example.com"
  [ "$status" -eq 1 ]
}

@test "chrome: _chrome_default_profile_matches fails when work domain missing" {
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  local state="$TEST_DIR/wrong-domain.json"
  cat > "$state" <<'JSON'
{
  "profile": {
    "last_used": "Profile 1",
    "info_cache": {
      "Profile 1": {"user_name": "alice@personal.com"}
    },
    "show_picker_on_startup": false
  }
}
JSON
  run _chrome_default_profile_matches "$state" "example.com"
  [ "$status" -eq 1 ]
}

@test "chrome: _chrome_default_profile_matches fails when picker is enabled" {
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  local state="$TEST_DIR/picker-on.json"
  cat > "$state" <<'JSON'
{
  "profile": {
    "last_used": "Profile 1",
    "info_cache": {
      "Profile 1": {"user_name": "alice@example.com"}
    },
    "show_picker_on_startup": true
  }
}
JSON
  run _chrome_default_profile_matches "$state" "example.com"
  [ "$status" -eq 1 ]
}

@test "chrome: _chromework_router_correct returns 0 for a valid ChromeWork router" {
  IS_ENTERPRISE=true
  mkdir -p "$TEST_HOME/Applications/ChromeWork.app/Contents/Resources/Scripts"
  cat > "$TEST_HOME/Applications/ChromeWork.app/Contents/Resources/Scripts/main.scpt" <<EOF
on routeURL(this_URL)
	my activateWorkChrome()
	do shell script quoted form of "$DOTFILES_DIR/bin/chromework-open-url" & " --no-activate " & quoted form of this_URL
	repeat 8 times
		my activateWorkChrome()
		delay 0.1
	end repeat
	do shell script quoted form of "$DOTFILES_DIR/bin/chromework-activate" & " --survive-handoff >/dev/null 2>&1 &"
end routeURL

on activateWorkChrome()
	tell application "Google Chrome"
		if (count of windows) > 0 then activate
	end tell
end activateWorkChrome
EOF
  /usr/bin/plutil -create xml1 "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  plutil -replace OSAAppletShowStartupScreen -bool false "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  plutil -replace LSUIElement -bool true "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  mkdir -p "$DOTFILES_DIR/bin"
  cat > "$DOTFILES_DIR/bin/chromework-open-url" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$DOTFILES_DIR/bin/chromework-open-url"

  # osadecompile stub reads the plain-text main.scpt our fake router writes.
  stub_bin="$TEST_DIR/stub-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/osadecompile" <<'EOF'
#!/bin/bash
cat "$1/Contents/Resources/Scripts/main.scpt"
EOF
  chmod +x "$stub_bin/osadecompile"
  export PATH="$stub_bin:$PATH"

  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  run _chromework_router_correct "example.com"
  [ "$status" -eq 0 ]
}

@test "chrome: ChromeWork router uses the applied checkout helper" {
  local applied="$TEST_DIR/applied"
  mkdir -p "$applied/bin" "$TEST_HOME/Applications/ChromeWork.app/Contents/Resources/Scripts"
  cat > "$applied/bin/chromework-open-url" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$applied/bin/chromework-open-url"
  cat > "$TEST_HOME/Applications/ChromeWork.app/Contents/Resources/Scripts/main.scpt" <<EOF
on routeURL(this_URL)
  do shell script quoted form of "$applied/bin/chromework-open-url" & " --no-activate " & quoted form of this_URL
end routeURL
on activateWorkChrome()
  do shell script "$applied/bin/chromework-activate --survive-handoff --no-activate"
end activateWorkChrome
EOF
  /usr/bin/plutil -create xml1 "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  plutil -replace OSAAppletShowStartupScreen -bool false "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  plutil -replace LSUIElement -bool true "$TEST_HOME/Applications/ChromeWork.app/Contents/Info.plist"
  local stub_bin="$TEST_DIR/stub-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/osadecompile" <<'EOF'
#!/bin/bash
cat "$1/Contents/Resources/Scripts/main.scpt"
EOF
  chmod +x "$stub_bin/osadecompile"
  export PATH="$stub_bin:$PATH"
  DOTFILES_LINK_DIR="$applied"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  run _chromework_router_correct "example.com"
  [ "$status" -eq 0 ]
}

@test "chrome: _chromework_is_default_browser accepts ChromeWork default" {
  stub_bin="$TEST_DIR/stub-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/defaultbrowser" <<'EOF'
#!/bin/bash
echo "* browser"
EOF
  chmod +x "$stub_bin/defaultbrowser"
  export PATH="$stub_bin:$PATH"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  run _chromework_is_default_browser
  [ "$status" -eq 0 ]
}

@test "chrome: _chromework_is_default_browser rejects raw Chrome default" {
  stub_bin="$TEST_DIR/stub-bin"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/defaultbrowser" <<'EOF'
#!/bin/bash
echo "* chrome"
EOF
  chmod +x "$stub_bin/defaultbrowser"
  export PATH="$stub_bin:$PATH"
  source "$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  run _chromework_is_default_browser
  [ "$status" -eq 1 ]
}

@test "chrome: module severity is important" {
  [ "$(cat "$BATS_TEST_DIRNAME/../modules/chrome/severity")" = "important" ]
}

@test "chrome: doctor.sh no longer embeds inline Python in check command string" {
  # The pre-refactor module had a multi-line Python heredoc embedded
  # in the `check` test_cmd. That made the snippet hard to lint and
  # impossible to unit-test. Pin the new shape: the inline `python3`
  # invocation is gone from the `check` line and only appears inside
  # the helper function definition.
  local doctor="$BATS_TEST_DIRNAME/../modules/chrome/doctor.sh"
  awk '/^if \[ "\$IS_ENTERPRISE"/,/^fi$/' "$doctor" | grep -q 'python3' && {
    echo "modules/chrome/doctor.sh still embeds python3 inside the enterprise check block"
    return 1
  }
  # And the helper function must exist.
  grep -q '^_chrome_default_profile_matches()' "$doctor" || {
    echo "modules/chrome/doctor.sh is missing the _chrome_default_profile_matches helper"
    return 1
  }
}

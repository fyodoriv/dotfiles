#!/usr/bin/env bats
# Functional tests for modules/agent-browser/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.agent-browser/chrome-profile"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/launchagents"

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
  FAIL_MESSAGES="$TEST_DIR/fail-messages"
  : > "$FAIL_MESSAGES"

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); echo "$1" >> "$FAIL_MESSAGES"; }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

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

  # Create zshrc with expected patterns
  cat > "$TEST_DOTFILES/home/zshrc" <<'ZSHRC'
export AGENT_BROWSER_IDLE_TIMEOUT_MS=600000
export AGENT_BROWSER_DEFAULT_TIMEOUT=30000
ZSHRC

  # Create zshrc.ai-tools matching the wrapper + session-env wiring
  cat > "$TEST_DOTFILES/home/zshrc.ai-tools" <<'ZSHRC_AI'
. "${DOTFILES_DIR}/lib/agent-browser-session-env.sh"
agent-browser-singleton-preflight
dotfiles-restore-focus-after-chrome
agent-browser() {
  if [ -z "$AGENT_BROWSER_NO_AUTO_CDP" ]; then
    command agent-browser --cdp 9223 "$@"
  fi
}
_DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
ZSHRC_AI

  mkdir -p "$TEST_DOTFILES/bin"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-restore-focus-after-chrome" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-restore-focus-after-chrome"
  cat > "$TEST_DOTFILES/bin/agent-browser-singleton-preflight" <<'HELPER'
#!/bin/bash
exit 0
HELPER
  cat > "$TEST_DOTFILES/bin/agent-browser-reap-strays" <<'HELPER'
#!/bin/bash
exit "${REAP_STRAYS_STATUS:-0}"
HELPER
  chmod +x "$TEST_DOTFILES/bin/agent-browser-singleton-preflight" "$TEST_DOTFILES/bin/agent-browser-reap-strays"

  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/agent-browser-session-env.sh" "$TEST_DOTFILES/lib/"
  cp "$BATS_TEST_DIRNAME/../lib/focus-steal-audit.sh" "$TEST_DOTFILES/lib/"
  mkdir -p "$TEST_DOTFILES/dot_config/dotfiles"
  cp "$BATS_TEST_DIRNAME/../dot_config/dotfiles/env.sh.tmpl" "$TEST_DOTFILES/dot_config/dotfiles/"
  cp "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl" "$TEST_DOTFILES/launchagents/"
  cp "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.debug-chrome.plist.tmpl" "$TEST_DOTFILES/launchagents/"
  cp "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.tooling-chrome.plist.tmpl" "$TEST_DOTFILES/launchagents/"

  # Mock spotlight exclusion
  touch "$TEST_HOME/.agent-browser/.metadata_never_index"

  # Mock agent-browser binary
  mkdir -p "$TEST_DIR/bin"
  echo '#!/bin/bash' > "$TEST_DIR/bin/agent-browser"
  chmod +x "$TEST_DIR/bin/agent-browser"
  export PATH="$TEST_DIR/bin:$PATH"

  # Mock curl to avoid real network call (CDP check)
  curl() { return 1; }

  REMOTE_DEBUGGING_COMMANDS=""
  ps() {
    if [ "${1:-}" = "-axo" ] && [ "${2:-}" = "command" ]; then
      printf '%s\n' "$REMOTE_DEBUGGING_COMMANDS"
      return 0
    fi
    command ps "$@"
  }

  # Clear agent-context env so the agent_session_isolation check has a
  # deterministic baseline (no agent context → check should pass). Tests
  # that want to simulate an agent context re-export these locally.
  unset DEVIN_MODEL DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  unset AGENT_BROWSER_SESSION
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "agent-browser: passes when profile dir and env vars exist" {
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  # installed + profile_dir + spotlight + idle_timeout + env_timeout should pass
  [ "$pass_count" -ge 4 ]
}

@test "agent-browser: fails when env patterns missing from zshrc" {
  echo "# empty" > "$TEST_DOTFILES/home/zshrc"
  rm -rf "$TEST_HOME/.agent-browser"
  rm -f "$TEST_DIR/bin/agent-browser"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fail_count" -ge 3 ]
}

@test "agent-browser: fix mode creates profile dir" {
  rm -rf "$TEST_HOME/.agent-browser/chrome-profile"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fix_count" -ge 1 ]
  [ -d "$TEST_HOME/.agent-browser/chrome-profile" ]
}

@test "agent-browser: overrides skip checks" {
  echo "agent-browser.installed" >> "$OVERRIDES_FILE"
  echo "agent-browser.profile_dir" >> "$OVERRIDES_FILE"
  echo "agent-browser.idle_timeout" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$skip_count" -ge 3 ]
}

@test "agent-browser: CLI missing fails installed check" {
  rm -f "$TEST_DIR/bin/agent-browser"
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "agent-browser: forwarded launch log line fails singleton log check" {
  mkdir -p "$TEST_HOME/.local/share/dotfiles/logs"
  echo "Opening in existing browser session." > "$TEST_HOME/.local/share/dotfiles/logs/agent-browser-chrome.log"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "launchd Chrome logs have no forwarded singleton launches" "$FAIL_MESSAGES"
}

@test "agent-browser: fix mode strips forwarded singleton lines from launchd logs" {
  mkdir -p "$TEST_HOME/.local/share/dotfiles/logs"
  printf '%s\n' "keep me" "Opening in existing browser session." "also keep" \
    > "$TEST_HOME/.local/share/dotfiles/logs/agent-browser-chrome.log"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "Opening in existing browser session." "$TEST_HOME/.local/share/dotfiles/logs/agent-browser-chrome.log" && return 1
  grep -q "keep me" "$TEST_HOME/.local/share/dotfiles/logs/agent-browser-chrome.log"
}

@test "agent-browser: stray target dry-run failure fails newtab target check" {
  export REAP_STRAYS_STATUS=1
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "managed Chromes expose no stray blank/newtab targets" "$FAIL_MESSAGES"
}

@test "agent-browser: duplicate managed Chrome process fails process-count check" {
  REMOTE_DEBUGGING_COMMANDS="$(cat <<'PROCS'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9223
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9224
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9225
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port 9223
PROCS
)"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "Managed Chrome process count stays at one per port" "$FAIL_MESSAGES"
}

@test "agent-browser: remote-debugging process-count check passes with exactly managed Chromes" {
  REMOTE_DEBUGGING_COMMANDS="$(cat <<'PROCS'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9223
/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/149.0.7827.103/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --remote-debugging-port=9223
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9224
/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/149.0.7827.103/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer) --type=renderer --remote-debugging-port=9224
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port 9225
PROCS
)"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  ! grep -q "Managed Chrome process count stays at one per port" "$FAIL_MESSAGES"
}

@test "agent-browser: remote-debugging process-count ignores headed SSO sessions" {
  REMOTE_DEBUGGING_COMMANDS="$(cat <<'PROCS'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9223
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9224
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9225
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9333
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port 9444
PROCS
)"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  ! grep -q "Managed Chrome process count stays at one per port" "$FAIL_MESSAGES"
}

@test "agent-browser: remote-debugging process-count check ignores its own regex" {
  REMOTE_DEBUGGING_COMMANDS="$(cat <<'PROCS'
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9223
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port=9224
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --remote-debugging-port 9225
/usr/bin/awk /--remote-debugging-port([= ]|$)/{count++}
PROCS
)"
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  ! grep -q "Managed Chrome process count stays at one per port" "$FAIL_MESSAGES"
}

@test "agent-browser: legacy launcher targeting managed profile fails safety check" {
  mkdir -p "$TEST_HOME/.agent-browser"
  cat > "$TEST_HOME/.agent-browser/launch-chrome.sh" <<'SCRIPT'
#!/bin/bash
/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --user-data-dir="$HOME/.agent-browser/chrome-profile"
SCRIPT
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "legacy agent-browser launch scripts do not launch managed profiles" "$FAIL_MESSAGES"
}

@test "agent-browser: KeepAlive=true in managed Chrome template fails shutdown-safe check" {
  local plist="$TEST_DOTFILES/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl"
  awk '
    /<key>KeepAlive<\/key>/ { seen = 1; print; next }
    seen && /<false\/>/ { print "  <true/>"; seen = 0; next }
    { print }
  ' "$plist" > "$plist.next"
  mv "$plist.next" "$plist"

  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "managed Chromes do not KeepAlive-reopen during logout/shutdown" "$FAIL_MESSAGES"
}

@test "agent-browser: fix mode creates spotlight exclusion file" {
  rm -f "$TEST_HOME/.agent-browser/.metadata_never_index"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ -f "$TEST_HOME/.agent-browser/.metadata_never_index" ]
}

# ── Per-agent daemon identity checks (2026-05-12 tab-hijacking fix) ──

@test "agent-browser: session-wired check passes when session env lib is wired" {
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q 'AGENT_BROWSER_SESSION="devin-' "$TEST_DOTFILES/lib/agent-browser-session-env.sh"
  grep -q 'agent-browser-session-env.sh' "$TEST_DOTFILES/home/zshrc.ai-tools"
}

@test "agent-browser: session-wired check fails when session env lib is missing" {
  rm -f "$TEST_DOTFILES/lib/agent-browser-session-env.sh"
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "agent-browser: session-isolation check passes when not in an agent context" {
  # setup() unsets DEVIN_MODEL etc., so this is the operator case.
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  # The session_isolation check should be in the pass tally because the
  # left side of `[ -z ... ] || { ... }` is true (no agent context).
  # Combined with the other checks, pass_count should be at the maximum.
  [ "$pass_count" -ge 8 ]
}

@test "agent-browser: session-isolation check fails when in agent context with no session" {
  export DEVIN_MODEL=claude-opus-4-8-max
  unset AGENT_BROWSER_SESSION
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "agent-browser: session-isolation check passes when agent context has a named session" {
  export DEVIN_MODEL=claude-opus-4-8-max
  export AGENT_BROWSER_SESSION=devin-abc12345
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  # session is "devin-abc12345" (not "default"), so the right side
  # `[ -n "$AGENT_BROWSER_SESSION" ] && [ ... != default ]` is true → pass.
  [ "$pass_count" -ge 8 ]
}

@test "agent-browser: session-isolation check fails when agent context has 'default' session" {
  export DEVIN_MODEL=claude-opus-4-8-max
  export AGENT_BROWSER_SESSION=default
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "agent-browser: restore_no_activate fails when helper hides Chrome via System Events" {
  echo 'osascript -e "tell process \"Google Chrome\" to set visible to false"' >> "$TEST_DOTFILES/bin/dotfiles-restore-focus-after-chrome"
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "focus-restore helper never osascript-activates or hides Chrome" "$FAIL_MESSAGES"
}

@test "agent-browser: focus.no_osascript_activate fails on activate in lib/" {
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/focus-steal-audit.sh" "$TEST_DOTFILES/lib/"
  echo 'osascript -e "tell application \"Foo\" to activate"' >> "$TEST_DOTFILES/lib/evil.sh"
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "no osascript 'to activate'" "$FAIL_MESSAGES"
}

@test "agent-browser: focus.no_steal_open_flags fails on open -a without -g" {
  cat > "$TEST_DOTFILES/bin/bad-open" <<'SCRIPT'
#!/bin/bash
open -a Safari
SCRIPT
  chmod +x "$TEST_DOTFILES/bin/bad-open"
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "open -a in bin/lib/launchagents uses -g" "$FAIL_MESSAGES"
}

@test "agent-browser: focus audit ignores AppleScript comments mentioning open -a" {
  cat > "$TEST_DOTFILES/macos-apps.sh" <<'SCRIPT'
-- launched headlessly by open -a URL
SCRIPT
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  ! grep -q "open -a in bin/lib/launchagents uses -g" "$FAIL_MESSAGES"
}

@test "agent-browser: launchagent_headless fails when --headless=new missing from plist" {
  local plist="$TEST_DOTFILES/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl"
  awk '!/--headless=new/' "$plist" > "$plist.next"
  mv "$plist.next" "$plist"
  pass_count=0
  fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/agent-browser/doctor.sh"
  grep -q "managed Chromes use --headless=new" "$FAIL_MESSAGES"
}

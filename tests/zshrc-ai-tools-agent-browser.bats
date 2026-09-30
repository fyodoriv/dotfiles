#!/usr/bin/env bats

ZSHRC_AI_TOOLS="$BATS_TEST_DIRNAME/../home/zshrc.ai-tools"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export DOTFILES_DIR="$TEST_DIR/dotfiles"
  unset AGENT_BROWSER_NO_AUTO_CDP AGENT_BROWSER_PROFILE AGENT_BROWSER_SESSION AGENT_BROWSER_ARGS
  unset DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  unset _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
  mkdir -p "$HOME/.agent-browser/chrome-profile" "$DOTFILES_DIR/bin" "$TEST_DIR/bin"
  PATH="$TEST_DIR/bin:$PATH"
  export PATH
  export _DOTFILES_AGENT_BROWSER_TEST_CDP_READY=1
  cat > "$TEST_DIR/bin/agent-browser" <<'MOCK_AGENT_BROWSER'
#!/bin/bash
printf 'real agent-browser: %s\n' "$*"
MOCK_AGENT_BROWSER
  chmod +x "$TEST_DIR/bin/agent-browser"
  PREFLIGHT_LOG="$TEST_DIR/preflight.log"
  cat > "$DOTFILES_DIR/bin/agent-browser-singleton-preflight" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$PREFLIGHT_LOG"
printf 'preflight called\n'
MOCK
  chmod +x "$DOTFILES_DIR/bin/agent-browser-singleton-preflight"
  export PREFLIGHT_LOG
}

teardown() {
  rm -rf "$TEST_DIR"
}

source_agent_browser_function() {
  local fn_text
  fn_text="$(awk 'flag && /^# ── PATH/{exit} /^_dotfiles_agent_browser_should_restore_focus\(\) \{/{flag=1} flag{print}' "$ZSHRC_AI_TOOLS")"
  [ -n "$fn_text" ] || return 1
  eval "$fn_text"
}

source_agent_session_block() {
  local block_text
  block_text="$(awk 'flag && /^# Wrap `agent-browser`/{exit} /^# Per-agent daemon identity/{flag=1} flag{print}' "$ZSHRC_AI_TOOLS")"
  [ -n "$block_text" ] || return 1
  eval "$block_text"
}

@test "agent-browser wrapper delegates launchd-owned profile to singleton preflight" {
  source_agent_browser_function
  export AGENT_BROWSER_PROFILE="$HOME/.agent-browser/chrome-profile"

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "preflight called" ]
  grep -q -- "--profile $HOME/.agent-browser/chrome-profile -- open https://example.com" "$PREFLIGHT_LOG"
}

@test "agent-browser wrapper refuses launchd-owned profile when preflight helper is unavailable" {
  rm -f "$DOTFILES_DIR/bin/agent-browser-singleton-preflight"
  source_agent_browser_function
  export AGENT_BROWSER_PROFILE="$HOME/.agent-browser/chrome-profile"

  run agent-browser open https://example.com

  [ "$status" -eq 2 ]
  [[ "$output" == *"Refusing to launch Chrome against launchd-owned AGENT_BROWSER_PROFILE"* ]]
}

@test "agent-browser wrapper fallback refuses tilde-spelled managed profile" {
  rm -f "$DOTFILES_DIR/bin/agent-browser-singleton-preflight"
  source_agent_browser_function
  export AGENT_BROWSER_PROFILE="~/.agent-browser/debug-profile"

  run agent-browser open https://example.com

  [ "$status" -eq 2 ]
  [[ "$output" == *"Refusing to launch Chrome against launchd-owned AGENT_BROWSER_PROFILE"* ]]
}

@test "agent-browser wrapper fallback refuses literal HOME-spelled managed profile" {
  rm -f "$DOTFILES_DIR/bin/agent-browser-singleton-preflight"
  source_agent_browser_function
  export AGENT_BROWSER_PROFILE='$HOME/.agent-browser/tooling-profile'

  run agent-browser open https://example.com

  [ "$status" -eq 2 ]
  [[ "$output" == *"Refusing to launch Chrome against launchd-owned AGENT_BROWSER_PROFILE"* ]]
}

@test "agent-browser wrapper attaches known agent contexts to managed CDP by default" {
  local envvar
  for envvar in DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT; do
    unset DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
    unset AGENT_BROWSER_PROFILE AGENT_BROWSER_SESSION AGENT_BROWSER_NO_AUTO_CDP _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
    export "$envvar=agent-context"
    source_agent_session_block
    source_agent_browser_function

    run agent-browser open https://example.com

    [ "$status" -eq 0 ]
    [ "${_DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION:-}" = "1" ]
    [ "$output" = "real agent-browser: --cdp 9223 open https://example.com" ]
  done
  unset DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  unset AGENT_BROWSER_SESSION _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
}

@test "agent-browser session block does not classify DEVIN_MODEL-only operator shells as agent sessions" {
  unset DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  unset AGENT_BROWSER_SESSION _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
  export DEVIN_MODEL="gpt-5-5-xhigh-priority"

  source_agent_session_block

  [ -z "${AGENT_BROWSER_SESSION:-}" ]
  [ -z "${_DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION:-}" ]
}

@test "agent-browser wrapper preserves explicit isolated sessions" {
  unset DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
  unset _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION
  source_agent_browser_function
  export DEVIN_SESSION_ID="devin-test"
  export AGENT_BROWSER_SESSION="explicit-isolated"

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "real agent-browser: open https://example.com" ]
}

@test "agent-browser wrapper auto-CDP opt-out does not bypass managed profile preflight" {
  source_agent_browser_function
  export AGENT_BROWSER_NO_AUTO_CDP=1
  export AGENT_BROWSER_PROFILE="$HOME/.agent-browser/chrome-profile"

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "preflight called" ]
  grep -q -- "--profile $HOME/.agent-browser/chrome-profile -- open https://example.com" "$PREFLIGHT_LOG"
}

@test "agent-browser wrapper logs focus steal after command when helper is available" {
  cat > "$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome" <<'MOCK_RESTORE'
#!/bin/bash
case "${1:-}" in
  --log-if-chrome-frontmost) printf 'log:%s\n' "${2:-}" ;;
  *) printf 'unexpected:%s\n' "$*" ;;
esac
MOCK_RESTORE
  chmod +x "$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome"
  source_agent_browser_function

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = $'real agent-browser: --cdp 9223 open https://example.com\nlog:' ]
}

@test "agent-browser wrapper skips focus log when --headed is passed" {
  cat > "$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome" <<'MOCK_RESTORE'
#!/bin/bash
case "${1:-}" in
  --log-if-chrome-frontmost) printf 'log:%s\n' "${2:-}" ;;
  *) printf 'unexpected:%s\n' "$*" ;;
esac
MOCK_RESTORE
  chmod +x "$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome"
  source_agent_browser_function

  run agent-browser --headed open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "real agent-browser: --cdp 9223 --headed open https://example.com" ]
}

@test "agent-browser wrapper omits AGENT_BROWSER_ARGS on CDP attach path" {
  cat > "$TEST_DIR/bin/agent-browser" <<'MOCK'
#!/bin/bash
printf 'args=%s env=%s\n' "$*" "${AGENT_BROWSER_ARGS-<unset>}"
MOCK
  chmod +x "$TEST_DIR/bin/agent-browser"
  source_agent_browser_function
  export AGENT_BROWSER_ARGS=--headless=new

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "args=--cdp 9223 open https://example.com env=<unset>" ]
}

@test "agent-browser wrapper applies headless args only on cold path" {
  unset _DOTFILES_AGENT_BROWSER_TEST_CDP_READY
  export AGENT_BROWSER_NO_AUTO_CDP=1
  cat > "$TEST_DIR/bin/agent-browser" <<'MOCK'
#!/bin/bash
printf 'args=%s env=%s\n' "$*" "${AGENT_BROWSER_ARGS-<unset>}"
MOCK
  chmod +x "$TEST_DIR/bin/agent-browser"
  source_agent_browser_function

  run agent-browser open https://example.com

  [ "$status" -eq 0 ]
  [ "$output" = "args=open https://example.com env=--headless=new" ]
}

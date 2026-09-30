#!/usr/bin/env bats
# Pin the `dvb()` GITHUB_TOKEN pre-export behavior in `home/zshrc.ai-tools`.
#
# Why this exists
# ---------------
# Devin for Terminal imports MCP configs from peer agents (~/.cursor/mcp.json,
# ~/.claude.json, ~/.codeium/windsurf/mcp_config.json, …) and strict-interpolates
# every `${VAR}` placeholder. A bare placeholder with an unset env var aborts
# Devin's WHOLE MCP load — playwright, context7, tasks-mcp all silently die.
#
# `~/.zshenv.secrets` derives GITHUB_TOKEN from `gh auth token` at parent-shell
# init, but the var is empty whenever `gh auth login` ran AFTER that shell
# started. The dvb wrapper re-derives at every invocation as a defensive
# second layer. These tests anchor that behavior so it can't silently regress.
#
# Reproduces the original fix from dotfiles PR #60.

load test_helper

# Path to the actual dvb function definition we're testing.
ZSHRC_AI_TOOLS="$BATS_TEST_DIRNAME/../home/zshrc.ai-tools"

# ── Setup ────────────────────────────────────────────────────────────────────

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_BIN="$TEST_DIR/bin"
  mkdir -p "$TEST_BIN"

  # Mock `devin` so dvb returns immediately. The wrapper passes through to
  # devin and we don't want to actually launch a session in a test.
  cat > "$TEST_BIN/devin" <<'MOCK'
#!/bin/bash
# devin mock — echoes args to MOCK_LOG for inspection, then exits 0.
echo "devin called: $*" >> "${MOCK_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$TEST_BIN/devin"

  export MOCK_LOG="$TEST_DIR/mock-devin.log"
  : > "$MOCK_LOG"

  # PATH layout: TEST_BIN first so our mocks win. /usr/bin so date/rm work.
  ORIGINAL_PATH="$PATH"
  export PATH="$TEST_BIN:/usr/bin:/bin"
}

teardown() {
  rm -rf "$TEST_DIR"
  export PATH="${ORIGINAL_PATH:-$PATH}"
}

# ── Mock helpers ──────────────────────────────────────────────────────────────

install_gh_mock() {
  # $1 — text to emit as the "auth token". Empty/omitted means failure.
  local token="${1:-}"
  cat > "$TEST_BIN/gh" <<MOCK
#!/bin/bash
if [ "\$1" = "auth" ] && [ "\$2" = "token" ]; then
  $( [ -n "$token" ] && echo "echo '$token'; exit 0" || echo "exit 1" )
fi
exit 1
MOCK
  chmod +x "$TEST_BIN/gh"
}

remove_gh_mock() {
  rm -f "$TEST_BIN/gh"
}

# Source the dvb function definition from zshrc.ai-tools without sourcing the
# rest of the file (which contains zsh-specific syntax bash can't parse).
# Extract the dvb function block + the helper variables it references.
source_dvb_function() {
  # Helper variables the function uses (defined just above dvb in the source file).
  _DV_GRIND_REQUEST="$TEST_DIR/grind-request"
  _DV_START_EPOCH=""

  # Stub the helpers dvb calls. We don't test their behavior here; just confirm
  # dvb completes without errors and the GITHUB_TOKEN export side-effect happens.
  _dv_show_duration() { :; }
  _dv_grind_handoff() { :; }

  # Pull out the dvb function definition from zshrc.ai-tools and eval it.
  # The bash-compatible block runs from `dvb() {` to the matching `}`.
  local fn_text
  fn_text="$(awk '/^dvb\(\) \{/,/^\}/' "$ZSHRC_AI_TOOLS")"
  if [ -z "$fn_text" ]; then
    echo "FATAL: could not extract dvb() from $ZSHRC_AI_TOOLS"
    return 1
  fi
  eval "$fn_text"
}

# ── Tests ─────────────────────────────────────────────────────────────────────

@test "dvb: exports GITHUB_TOKEN from gh auth token when unset and gh available" {
  install_gh_mock "ghp_fixture_token_abc123"
  unset GITHUB_TOKEN

  source_dvb_function
  dvb

  # The function should have pre-exported the mocked token.
  [ "$GITHUB_TOKEN" = "ghp_fixture_token_abc123" ]
}

@test "dvb: does NOT override GITHUB_TOKEN when it is already set" {
  install_gh_mock "ghp_different_token"
  export GITHUB_TOKEN="ghp_preset_token"

  source_dvb_function
  dvb

  # The pre-set value must survive — dvb should be idempotent here.
  [ "$GITHUB_TOKEN" = "ghp_preset_token" ]
}

@test "dvb: leaves GITHUB_TOKEN empty when gh is missing from PATH" {
  remove_gh_mock
  unset GITHUB_TOKEN

  source_dvb_function
  dvb

  # No gh → no token. dvb must NOT crash and must NOT export anything.
  [ -z "${GITHUB_TOKEN:-}" ]
}

@test "dvb: leaves GITHUB_TOKEN empty when gh auth token fails (e.g. logged out)" {
  install_gh_mock ""  # gh exists but `gh auth token` exits 1
  unset GITHUB_TOKEN

  source_dvb_function
  dvb

  # Failing gh auth → empty value. The export still happens but with empty
  # content — that's fine because Devin's interpolator treats empty same as unset
  # for ${VAR:-} placeholders, and resilient configs handle it.
  [ -z "${GITHUB_TOKEN:-}" ]
}

@test "dvb: invokes the (mocked) devin binary downstream" {
  install_gh_mock "ghp_token"
  unset GITHUB_TOKEN

  source_dvb_function
  dvb --some-flag value

  # devin should have been invoked with the trailing args. Confirms the
  # GITHUB_TOKEN block doesn't short-circuit the rest of dvb.
  grep -q "devin called: " "$MOCK_LOG"
}

@test "dvb: function definition contains the documented GITHUB_TOKEN block" {
  # Defensive: if a future refactor removes the block, this test fires
  # before the behavioral tests above mask the regression (e.g. by
  # changing how the block reads gh auth).
  grep -q 'GITHUB_TOKEN.*gh auth token' "$ZSHRC_AI_TOOLS"
}

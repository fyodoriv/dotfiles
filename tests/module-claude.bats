#!/usr/bin/env bats
# Functional tests for modules/claude/doctor.sh
#
# After the OSS split, the only check this module owns is the
# `claude.model_wrapper` wrapper. Any company-specific branch lives in
# an overlay module loaded via the EXTRA_DOCTOR_DIR hook.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

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

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
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
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "claude: wrapper check passes when ~/bin/claude strips ANTHROPIC_MODEL" {
  mkdir -p "$TEST_HOME/bin" "$TEST_HOME/.claude" "$TEST_HOME/.local/bin"
  touch "$TEST_HOME/.local/bin/claude"
  echo '{"model":"claude-opus-5-5","effortLevel":"medium","permissions":{"defaultMode":"bypassPermissions"},"skipAutoPermissionPrompt":true}' > "$TEST_HOME/.claude/settings.json"
  cat > "$TEST_HOME/bin/claude" <<'WRAPPER'
#!/bin/bash
unset ANTHROPIC_MODEL
# default-permission-mode-bypass
exec "$HOME/.local/bin/claude" "$@"
WRAPPER

  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"

  [ "$pass_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "claude: wrapper check fails when unmanaged wrapper is missing" {
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"

  [ "$pass_count" -eq 1 ]
  [ "$fail_count" -eq 2 ]
}

@test "claude: doctor module registers expected checks" {
  # Pin the module's surface so a future re-introduction of any
  # company-specific check would have to update this assertion.
  LIST_MODE=true
  collected=()
  check() { collected+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "${#collected[@]}" -eq 3 ]
  [ "${collected[0]}" = "claude.model_wrapper" ]
  [ "${collected[1]}" = "claude.model_default" ]
  [ "${collected[2]}" = "claude.observe_plugin_server" ]
}

@test "claude: observe check fails when the plugin is enabled and its server is down" {
  mkdir -p "$TEST_HOME/.claude"
  echo '{"enabledPlugins":{"agents-observe@agents-observe":true}}' > "$TEST_HOME/.claude/settings.json"
  export AGENTS_OBSERVE_SERVER_PORT=1
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  run _claude_observe_plugin_ok
  [ "$status" -ne 0 ]
}

@test "claude: observe check passes when the server is idle but Docker answers" {
  mkdir -p "$TEST_HOME/.claude" "$TEST_DIR/stubs"
  echo '{"enabledPlugins":{"agents-observe@agents-observe":true}}' > "$TEST_HOME/.claude/settings.json"
  printf '#!/bin/bash\ncase "$*" in *unix-socket*) exit 0 ;; *) exit 7 ;; esac\n' > "$TEST_DIR/stubs/curl"
  chmod +x "$TEST_DIR/stubs/curl"
  export AGENTS_OBSERVE_SERVER_PORT=1
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  PATH="$TEST_DIR/stubs:$PATH" run _claude_observe_plugin_ok
  [ "$status" -eq 0 ]
}

@test "claude: observe repair starts Rancher Desktop" {
  check() { [ "$1" = "claude.observe_plugin_server" ] && echo "$4" > "$TEST_DIR/fix_cmd"; return 0; }
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$(cat "$TEST_DIR/fix_cmd")" = "bash '$DOTFILES_DIR/bin/rancher-desktop'" ]
}

@test "claude: observe check passes when the plugin is disabled" {
  mkdir -p "$TEST_HOME/.claude"
  echo '{"enabledPlugins":{"agents-observe@agents-observe":false}}' > "$TEST_HOME/.claude/settings.json"
  export AGENTS_OBSERVE_SERVER_PORT=1
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  run _claude_observe_plugin_ok
  [ "$status" -eq 0 ]
}

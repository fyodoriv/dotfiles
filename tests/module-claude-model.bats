#!/usr/bin/env bats
# Functional tests for modules/claude/doctor.sh — claude.model_default check
# and the chezmoi script that fixes it.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME/.claude"
  mkdir -p "$TEST_HOME/.local/bin"
  mkdir -p "$TEST_HOME/bin"
  mkdir -p "$TEST_DOTFILES/.chezmoiscripts"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  # Resolve the base default unless a test sets an override on purpose.
  unset DOTFILES_CLAUDE_MODEL DOTFILES_CLAUDE_EFFORT XDG_CONFIG_HOME

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

  # Pretend claude is installed (the doctor short-circuits if ~/.local/bin/claude
  # is absent — we want the model_default check to actually evaluate).
  touch "$TEST_HOME/.local/bin/claude"
  chmod +x "$TEST_HOME/.local/bin/claude"

  # Stub the wrapper installer so the unrelated claude.model_wrapper check passes.
  mkdir -p "$TEST_DOTFILES/.chezmoiscripts"
  echo "#!/bin/bash
echo '#!/bin/bash
# unset ANTHROPIC_MODEL  # marker for grep
# default-permission-mode-bypass
# remote-control-flags-after-verb
exec /placeholder' > \"\$HOME/bin/claude\"
chmod +x \"\$HOME/bin/claude\"" > "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"
  chmod +x "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  # Copy the real chezmoi model-pin script into the test DOTFILES_DIR so the
  # doctor's fix command can find it.
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_claude-settings-model.sh" \
     "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-settings-model.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "claude.model_default passes when settings.json has the correct pin" {
  echo '{"model":"claude-opus-5-5","effortLevel":"xhigh","permissions":{"defaultMode":"bypassPermissions"},"skipAutoPermissionPrompt":true}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -ge 2 ]  # both wrapper and model_default
}

@test "claude.model_default fails when settings.json has the wrong model" {
  echo '{"model":"claude-sonnet-4-6","effortLevel":"xhigh"}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fails when settings.json has the wrong effortLevel" {
  echo '{"model":"claude-opus-5-5","effortLevel":"medium"}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fails when settings.json has the wrong permission mode" {
  echo '{"model":"claude-opus-5-5","effortLevel":"xhigh","permissions":{"defaultMode":"default"},"skipAutoPermissionPrompt":true}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fails when settings.json is missing the model key" {
  echo '{"effortLevel":"xhigh","other":"stuff"}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fails when settings.json doesn't exist" {
  rm -f "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fix mode pins the model, effortLevel, and permission mode idempotently" {
  echo '{"model":"haiku","effortLevel":"low","hooks":{"PostToolUse":[{"matcher":"x"}]}}' \
    > "$TEST_HOME/.claude/settings.json"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fix_count" -ge 1 ]
  # Existing keys preserved (the hooks block must survive the jq merge)
  grep -q '"hooks"' "$TEST_HOME/.claude/settings.json"
  # New pin landed
  grep -q '"model"[[:space:]]*:[[:space:]]*"claude-opus-5-5"' "$TEST_HOME/.claude/settings.json"
  grep -q '"effortLevel"[[:space:]]*:[[:space:]]*"xhigh"' "$TEST_HOME/.claude/settings.json"
  grep -q '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"' "$TEST_HOME/.claude/settings.json"
  grep -q '"skipAutoPermissionPrompt"[[:space:]]*:[[:space:]]*true' "$TEST_HOME/.claude/settings.json"
}

@test "claude.model_default fix is idempotent on repeat runs" {
  echo '{"model":"haiku","effortLevel":"low"}' > "$TEST_HOME/.claude/settings.json"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  local first_mtime
  first_mtime=$(stat -f %m "$TEST_HOME/.claude/settings.json")
  sleep 1
  # Reset counters and re-run; the second pass should not touch the file
  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  local second_mtime
  second_mtime=$(stat -f %m "$TEST_HOME/.claude/settings.json")
  [ "$first_mtime" -eq "$second_mtime" ]
  [ "$fail_count" -eq 0 ]
}

@test "claude.model_default overrides skip checks" {
  echo '{"model":"haiku"}' > "$TEST_HOME/.claude/settings.json"
  echo "claude.model_default" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$skip_count" -ge 1 ]
}

# ── Base default and per-machine override ────────────────────────────
# The pin script resolves model/effort as: env > chezmoi data > base default.
# The doctor asks the script for the same pair, so check and fix agree.

_pin() {
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-settings-model.sh" "$@"
}

_settings_value() {
  jq -r "$1" "$TEST_HOME/.claude/settings.json"
}

_write_chezmoi_data() {
  mkdir -p "$TEST_HOME/.config/chezmoi"
  printf 'data:\n  claude_model: "%s"\n  claude_effort: "%s"\n' "$1" "$2" \
    > "$TEST_HOME/.config/chezmoi/chezmoi.yaml"
}

@test "claude pin: base default is claude-opus-5-5 at xhigh effort" {
  echo '{}' > "$TEST_HOME/.claude/settings.json"
  _pin
  [ "$(_settings_value .model)" = "claude-opus-5-5" ]
  [ "$(_settings_value .effortLevel)" = "xhigh" ]
  [ "$(_settings_value .permissions.defaultMode)" = "bypassPermissions" ]
  [ "$(_settings_value .skipAutoPermissionPrompt)" = "true" ]
}

@test "claude pin: --print-desired prints the resolved model and effort" {
  run _pin --print-desired
  [ "$status" -eq 0 ]
  [ "$output" = "claude-opus-5-5 xhigh" ]
}

@test "claude pin: DOTFILES_CLAUDE_MODEL and DOTFILES_CLAUDE_EFFORT override the base default" {
  echo '{"hooks":{"Stop":[]}}' > "$TEST_HOME/.claude/settings.json"
  DOTFILES_CLAUDE_MODEL="claude-example-model" DOTFILES_CLAUDE_EFFORT="high" _pin
  [ "$(_settings_value .model)" = "claude-example-model" ]
  [ "$(_settings_value .effortLevel)" = "high" ]
  # Permission behavior does not change with the override.
  [ "$(_settings_value .permissions.defaultMode)" = "bypassPermissions" ]
  [ "$(_settings_value .skipAutoPermissionPrompt)" = "true" ]
  [ "$(_settings_value '.hooks | has("Stop")')" = "true" ]
}

@test "claude pin: one env key overrides only that key" {
  echo '{}' > "$TEST_HOME/.claude/settings.json"
  DOTFILES_CLAUDE_EFFORT="low" _pin
  [ "$(_settings_value .model)" = "claude-opus-5-5" ]
  [ "$(_settings_value .effortLevel)" = "low" ]
}

@test "claude pin: chezmoi data claude_model and claude_effort override the base default" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  _write_chezmoi_data "claude-data-model" "low"
  echo '{}' > "$TEST_HOME/.claude/settings.json"
  _pin
  [ "$(_settings_value .model)" = "claude-data-model" ]
  [ "$(_settings_value .effortLevel)" = "low" ]
}

@test "claude pin: env override wins over chezmoi data" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  _write_chezmoi_data "claude-data-model" "low"
  run env DOTFILES_CLAUDE_MODEL="claude-env-model" bash \
    "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-settings-model.sh" --print-desired
  [ "$status" -eq 0 ]
  [ "$output" = "claude-env-model low" ]
}

@test "claude pin: an effort Claude Code cannot persist keeps the base default" {
  echo '{}' > "$TEST_HOME/.claude/settings.json"
  run env DOTFILES_CLAUDE_EFFORT="max" bash \
    "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-settings-model.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not persistable"* ]]
  [ "$(_settings_value .effortLevel)" = "xhigh" ]
}

@test "claude pin: MCP grants still sync when an override is set" {
  echo '{"permissions":{"allow":["Bash(ls:*)"]}}' > "$TEST_HOME/.claude/settings.json"
  echo '{"mcpServers":{"context7":{}}}' > "$TEST_HOME/.claude.json"
  DOTFILES_CLAUDE_EFFORT="high" _pin
  [ "$(_settings_value '.permissions.allow | any(. == "mcp__context7__*")')" = "true" ]
  [ "$(_settings_value '.permissions.allow | any(. == "Bash(ls:*)")')" = "true" ]
}

@test "claude.model_default passes for the override pair and fails for the base default under it" {
  export DOTFILES_CLAUDE_MODEL="claude-example-model" DOTFILES_CLAUDE_EFFORT="high"
  echo '{"model":"claude-example-model","effortLevel":"high","permissions":{"defaultMode":"bypassPermissions"},"skipAutoPermissionPrompt":true}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -eq 0 ]

  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  echo '{"model":"claude-opus-5-5","effortLevel":"xhigh","permissions":{"defaultMode":"bypassPermissions"},"skipAutoPermissionPrompt":true}' > "$TEST_HOME/.claude/settings.json"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "claude.model_default fix writes the chezmoi data override" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  _write_chezmoi_data "claude-data-model" "medium"
  echo '{"model":"claude-opus-5-5","effortLevel":"xhigh"}' > "$TEST_HOME/.claude/settings.json"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fix_count" -ge 1 ]
  [ "$(_settings_value .model)" = "claude-data-model" ]
  [ "$(_settings_value .effortLevel)" = "medium" ]

  pass_count=0; fail_count=0; fix_count=0; skip_count=0
  FIX_MODE=false
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  [ "$fail_count" -eq 0 ]
}

@test "claude.model_default without jq matches a bracketed override model literally" {
  local bin="$TEST_DIR/no-jq-bin"
  mkdir -p "$bin"
  ln -s /bin/bash "$bin/bash"
  ln -s /usr/bin/dirname "$bin/dirname"
  ln -s /usr/bin/grep "$bin/grep"
  ln -s /usr/bin/sed "$bin/sed"
  source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"
  export DOTFILES_CLAUDE_MODEL="claude-opus-5-5[1m]" DOTFILES_CLAUDE_EFFORT="high"

  echo '{"model": "claude-opus-5-5[1m]", "effortLevel": "high", "permissions": {"defaultMode": "bypassPermissions"}, "skipAutoPermissionPrompt": true}' > "$TEST_HOME/.claude/settings.json"
  PATH="$bin" _claude_model_is_default

  # Unescaped, [1m] would be a bracket expression that also matches "...-5-5m".
  echo '{"model": "claude-opus-5-5m", "effortLevel": "high", "permissions": {"defaultMode": "bypassPermissions"}, "skipAutoPermissionPrompt": true}' > "$TEST_HOME/.claude/settings.json"
  if PATH="$bin" _claude_model_is_default; then false; fi
}

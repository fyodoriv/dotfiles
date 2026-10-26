#!/usr/bin/env bats
# Tests for .chezmoiscripts/run_after_claude-disabled-plugins.sh and the
# claude.disabled_plugins / claude.no_context7_mcp doctor checks.
# Every test runs in a scratch HOME (test-process scope, removed in teardown).

load test_helper

SCRIPT_REL=".chezmoiscripts/run_after_claude-disabled-plugins.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export DOTFILES_DIR="$TEST_DIR/dotfiles"
  mkdir -p "$HOME/.claude" "$HOME/.local/bin" "$DOTFILES_DIR/.chezmoiscripts" "$TEST_DIR/bin"
  touch "$HOME/.local/bin/claude"
  cp "$BATS_TEST_DIRNAME/../$SCRIPT_REL" "$DOTFILES_DIR/$SCRIPT_REL"
  unset DOTFILES_CLAUDE_DISABLED_PLUGINS
  # No chezmoi data in a scratch HOME: the built-in default applies.
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH"
  S="$HOME/.claude/settings.json"

  checks=()
  check() { if eval "$3" >/dev/null 2>&1; then checks+=("pass $1"); else checks+=("fail $1|$2"); fi; }
  check_advisory() { check "$@"; }
}

teardown() { rm -rf "$TEST_DIR"; }

result_for() { local c; for c in "${checks[@]}"; do [[ "$c" == *" $1"* ]] && printf '%s\n' "$c"; done; return 0; }
run_doctor() { checks=(); source "$BATS_TEST_DIRNAME/../modules/claude/doctor.sh"; }

@test "apply turns a re-enabled synced plugin off and keeps other keys" {
  echo '{"model":"m","enabledPlugins":{"prisma@synced":true,"other@x":true}}' > "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.enabledPlugins["prisma@synced"]' "$S")" = "false" ]
  [ "$(jq -r '.enabledPlugins["other@x"]' "$S")" = "true" ]
  [ "$(jq -r '.model' "$S")" = "m" ]
}

@test "apply is idempotent: a second run leaves the file untouched" {
  echo '{"enabledPlugins":{"prisma@synced":false}}' > "$S"
  before="$(cat "$S")"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$S")" = "$before" ]
}

@test "the env list wins, and an empty env list manages nothing" {
  echo '{"enabledPlugins":{"prisma@synced":true,"a@b":true}}' > "$S"
  DOTFILES_CLAUDE_DISABLED_PLUGINS="a@b" run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$(jq -r '.enabledPlugins["a@b"]' "$S")" = "false" ]
  [ "$(jq -r '.enabledPlugins["prisma@synced"]' "$S")" = "true" ]
  DOTFILES_CLAUDE_DISABLED_PLUGINS="" run bash "$DOTFILES_DIR/$SCRIPT_REL" --print-list
  [ -z "$output" ]
}

@test "doctor fails when a listed plugin is on, and the fix turns it off" {
  echo '{"enabledPlugins":{"prisma@synced":true}}' > "$S"
  run_doctor
  [[ "$(result_for claude.disabled_plugins)" == fail* ]]
  bash "$DOTFILES_DIR/$SCRIPT_REL"
  run_doctor
  [[ "$(result_for claude.disabled_plugins)" == pass* ]]
}

@test "doctor has no Claude Desktop plugin line" {
  run_doctor
  ! printf '%s\n' "${checks[@]}" | grep -qi desktop
}

@test "doctor passes the context7 check on a clean config" {
  echo '{"mcpServers":{"shadcn":{}}}' > "$HOME/.claude.json"
  run_doctor
  [[ "$(result_for claude.no_context7_mcp)" == pass* ]]
}

@test "doctor fails and names the file when context7 is an MCP server in any agent config" {
  local d="$HOME/Library/Application Support/Claude"
  mkdir -p "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.local/share/dotfiles-vscode" "$d"
  local files=("$HOME/.claude.json" "$d/claude_desktop_config.json" "$HOME/.config/opencode/opencode.json" "$HOME/.local/share/dotfiles-vscode/settings.generated.json")
  local bodies=('{"projects":{"/x":{"mcpServers":{"context7":{}}}}}' '{"mcpServers":{"context7":{}}}' '{"mcp":{"context7":{}}}' '{"mcp":{"servers":{"context7":{}}}}')
  local i r
  for i in 0 1 2 3; do
    rm -f "${files[@]}"
    printf '%s' "${bodies[$i]}" > "${files[$i]}"
    run_doctor
    r="$(result_for claude.no_context7_mcp)"
    [[ "$r" == fail*"${files[$i]}"*"agentbrew sync"* ]] || { echo "not caught: ${files[$i]} -> $r"; return 1; }
  done
  rm -f "${files[@]}"
  printf '[mcp_servers.context7]\ncommand = "x"\n' > "$HOME/.codex/config.toml"
  run_doctor
  [[ "$(result_for claude.no_context7_mcp)" == fail*".codex/config.toml"* ]]
}

@test "a key named context7 outside an MCP block is not a server" {
  echo '{"notes":{"context7":"declined"}}' > "$HOME/.claude.json"
  run_doctor
  [[ "$(result_for claude.no_context7_mcp)" == pass* ]]
}

@test "apply refuses to overwrite a settings file that is not a JSON object" {
  printf '{not json' > "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to overwrite"* ]]
  [ "$(cat "$S")" = "{not json" ]
  echo '[1]' > "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 1 ]
  [ "$(cat "$S")" = "[1]" ]
}

@test "apply writes through a symlinked settings file and keeps the link" {
  mkdir -p "$TEST_DIR/real"
  echo '{"enabledPlugins":{"prisma@synced":true}}' > "$TEST_DIR/real/settings.json"
  ln -s "$TEST_DIR/real/settings.json" "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ -L "$S" ]
  [ "$(jq -r '.enabledPlugins["prisma@synced"]' "$TEST_DIR/real/settings.json")" = "false" ]
}

@test "apply keeps the settings file mode" {
  echo '{"enabledPlugins":{"prisma@synced":true}}' > "$S"
  chmod 640 "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ "$(stat -f '%Lp' "$S" 2>/dev/null || stat -c '%a' "$S")" = "640" ]
}

@test "an empty claude_disabled_plugins list in chezmoi data manages nothing" {
  printf '#!/bin/sh\nprintf ""\n' > "$TEST_DIR/bin/chezmoi"
  echo '{"enabledPlugins":{"prisma@synced":true}}' > "$S"
  run bash "$DOTFILES_DIR/$SCRIPT_REL" --print-list
  [ -z "$output" ]
  run bash "$DOTFILES_DIR/$SCRIPT_REL"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.enabledPlugins["prisma@synced"]' "$S")" = "true" ]
}

@test "a chezmoi data list replaces the default" {
  printf '#!/bin/sh\nprintf "a@b,c@d"\n' > "$TEST_DIR/bin/chezmoi"
  run bash "$DOTFILES_DIR/$SCRIPT_REL" --print-list
  [ "$output" = "$(printf 'a@b\nc@d')" ]
}

@test "doctor catches an indented context7 header in codex config.toml" {
  mkdir -p "$HOME/.codex"
  printf '  [mcp_servers.context7]\n  command = "x"\n' > "$HOME/.codex/config.toml"
  run_doctor
  [[ "$(result_for claude.no_context7_mcp)" == fail*".codex/config.toml"* ]]
}

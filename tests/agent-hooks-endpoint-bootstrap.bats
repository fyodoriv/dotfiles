#!/usr/bin/env bats

load test_helper

@test "bootstrap-endpoint-path: resolves jq via dotfiles/bin on sandbox PATH" {
  mkdir -p "$TEST_DOTFILES/bin"
  ln -sfn /opt/homebrew/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || ln -sfn /usr/local/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || true
  run env -u BASH_ENV -u ENV -i PATH=/opt/homebrew/bin:/usr/bin:/bin HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash -c \
    'source ./agent-hooks/bootstrap-endpoint-path.sh; command -v jq'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DOTFILES/bin/jq"* ]]
}

@test "bootstrap-endpoint-path: sets DOTFILES_JQ on sandbox PATH" {
  mkdir -p "$TEST_DOTFILES/bin"
  ln -sfn /opt/homebrew/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || ln -sfn /usr/local/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || true
  run env -u BASH_ENV -u ENV -i PATH=/opt/homebrew/bin:/usr/bin:/bin HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash -c \
    'source ./agent-hooks/bootstrap-endpoint-path.sh; printf "%s" "$DOTFILES_JQ"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DOTFILES/bin/jq"* ]]
}

@test "with-endpoint-path: exec resolves jq on sandbox PATH" {
  mkdir -p "$TEST_DOTFILES/bin"
  ln -sfn /opt/homebrew/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || ln -sfn /usr/local/bin/jq "$TEST_DOTFILES/bin/jq" 2>/dev/null || true
  run env -u BASH_ENV -u ENV -i PATH=/opt/homebrew/bin:/usr/bin:/bin HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash -c \
    './agent-hooks/with-endpoint-path.sh command -v jq'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DOTFILES/bin/jq"* ]]
}

@test "hooks-endpoint-wrap: wraps audit-logger commands idempotently" {
  mkdir -p "$TEST_HOME/.cursor" "$TEST_HOME/.config/dotfiles/hooks"
  cp ./agent-hooks/with-endpoint-path.sh "$TEST_HOME/.config/dotfiles/hooks/"
  chmod +x "$TEST_HOME/.config/dotfiles/hooks/with-endpoint-path.sh"
  cat > "$TEST_HOME/.cursor/hooks.json" <<'JSON'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {"command": "~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit"}
    ],
    "preToolUse": [
      {"matcher": "Shell", "command": "~/.config/dotfiles/hooks/prepend-endpoint-path.sh"}
    ]
  }
}
JSON
  HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash ./.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh
  cmd="$(/usr/bin/plutil -extract hooks.afterFileEdit.0.command raw -o - "$TEST_HOME/.cursor/hooks.json")"
  shell_cmd="$(/usr/bin/plutil -extract hooks.preToolUse.0.command raw -o - "$TEST_HOME/.cursor/hooks.json")"
  [[ "$cmd" == *with-endpoint-path* ]]
  [[ "$cmd" == *audit-logger* ]]
  [[ "$shell_cmd" != *with-endpoint-path* ]]
  # Second run must not double-wrap
  HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash ./.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh
  cmd="$(/usr/bin/plutil -extract hooks.afterFileEdit.0.command raw -o - "$TEST_HOME/.cursor/hooks.json")"
  remainder="${cmd#*with-endpoint-path}"
  [[ "$remainder" != *with-endpoint-path* ]]
}

@test "hooks-endpoint-wrap: collapses re-added codeassist hooks to one entry" {
  mkdir -p "$TEST_HOME/.cursor" "$TEST_HOME/.config/dotfiles/hooks"
  cp ./agent-hooks/with-endpoint-path.sh "$TEST_HOME/.config/dotfiles/hooks/"
  chmod +x "$TEST_HOME/.config/dotfiles/hooks/with-endpoint-path.sh"
  local wrapper="$TEST_HOME/.config/dotfiles/hooks/with-endpoint-path.sh"
  cat > "$TEST_HOME/.cursor/hooks.json" <<JSON
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [
      {"command": "$wrapper ~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit"},
      {"command": "$wrapper ~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit"},
      {"command": "~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit"}
    ],
    "preToolUse": [
      {"matcher": "Shell", "command": "~/.config/dotfiles/hooks/prepend-endpoint-path.sh"},
      {"matcher": "Bash", "command": "~/.config/dotfiles/hooks/prepend-endpoint-path.sh"}
    ]
  }
}
JSON
  run env HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" bash ./.chezmoiscripts/run_after_cursor-hooks-endpoint-wrap.sh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed 2 duplicate hook entries"* ]]
  [ "$(/usr/bin/plutil -extract hooks.afterFileEdit raw -o - "$TEST_HOME/.cursor/hooks.json")" = 1 ]
  [ "$(/usr/bin/plutil -extract hooks.preToolUse raw -o - "$TEST_HOME/.cursor/hooks.json")" = 2 ]
  cmd="$(/usr/bin/plutil -extract hooks.afterFileEdit.0.command raw -o - "$TEST_HOME/.cursor/hooks.json")"
  [ "$cmd" = "$wrapper ~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit" ]
}

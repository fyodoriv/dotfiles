#!/usr/bin/env bats

load test_helper
bats_require_minimum_version 1.5.0

@test "prepend-endpoint-path: allows non-shell tools unchanged" {
  run bash -c 'echo "{\"tool_name\": \"Read\", \"tool_input\": {}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permission": "allow"'* ]]
  [[ "$output" != *"updated_input"* ]]
}

@test "prepend-endpoint-path: prepends dotfiles/bin for Shell tool" {
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{\"tool_name\": \"Shell\", \"tool_input\": {\"command\": \"command -v ggrep\"}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permission"'* ]]
  [[ "$output" == *'"allow"'* ]]
  [[ "$output" == *"updated_input"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
  [[ "$output" == *"command -v ggrep"* ]]
}

@test "prepend-endpoint-path: emits a static PATH for push-guard classification" {
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV PATH="/usr/bin:/bin" \
    DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" /bin/bash -c \
    'echo "{\"tool_name\": \"Shell\", \"tool_input\": {\"command\": \"git push origin feature\"}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated_input"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
  [[ "$output" == *"/usr/bin:/bin"* ]]
  [[ "$output" != *'$PATH'* ]]
  [[ "$output" != *"export PATH="* ]]
}

@test "prepend-endpoint-path: prepends dotfiles/bin for Bash tool" {
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{\"tool_name\": \"Bash\", \"tool_input\": {\"command\": \"rg foo\"}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
}

@test "prepend-endpoint-path: skips double-prefix" {
  run bash -c "echo '{\"tool_name\": \"Shell\", \"tool_input\": {\"command\": \"export PATH=\\\"$TEST_DOTFILES/bin:\\\$PATH\\\"; echo ok\"}}' | ./agent-hooks/prepend-endpoint-path.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"updated_input"* ]]
}

@test "session-endpoint-path: emits PATH env with dotfiles/bin" {
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{}" | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"env"'* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
  [[ "$output" == *'"DOTFILES_DIR"'* ]]
}

@test "session-endpoint-path: appends quoted PATH to Claude's environment file" {
  local quoted_dotfiles="$TEST_HOME/dotfiles with a 'quote"
  local env_file="$TEST_HOME/claude-session.env"
  mkdir -p "$quoted_dotfiles/bin"
  printf '%s\n' 'export KEEP=fixture' >"$env_file"

  run env -u BASH_ENV -u ENV DOTFILES_DIR="$quoted_dotfiles" HOME="$TEST_HOME" \
    CLAUDE_ENV_FILE="$env_file" /bin/bash -c \
    'printf "%s\n" '"'"'{"hook_event_name":"SessionStart"}'"'"' | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg path "$quoted_dotfiles/bin" '.env.PATH | startswith($path + ":")'

  run env -u BASH_ENV -u ENV PATH="/usr/bin:/bin" /bin/bash -c \
    'source "$1"; printf "%s\n%s\n" "$KEEP" "$PATH"' bash "$env_file"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = fixture ]
  [[ "${lines[1]}" == "$quoted_dotfiles/bin:"* ]]
  [[ "${lines[1]}" == *":/usr/bin:/bin" ]]
}

@test "session-endpoint-path: leaves the environment file alone for legacy events" {
  local env_file="$TEST_HOME/claude-session.env"
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    CLAUDE_ENV_FILE="$env_file" /bin/bash -c 'printf "%s\n" "{}" | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [ ! -e "$env_file" ]
}

@test "session-endpoint-path: retains an active Agentbrew Git guard while adding shims" {
  local env_file="$TEST_HOME/claude-session.env"
  local guard="$TEST_HOME/.claude/codeassist/hooks-scripts/lib"
  mkdir -p "$TEST_DOTFILES/bin" "$guard"
  printf '#!/bin/bash\n' >"$guard/git"
  chmod +x "$guard/git"

  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    CLAUDE_ENV_FILE="$env_file" /bin/bash -c \
    'printf "%s\n" '"'"'{"hook_event_name":"SessionStart"}'"'"' | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]

  run env -u BASH_ENV -u ENV PATH="$guard:/usr/bin:/bin" /bin/bash -c \
    'source "$1"; command -v git; printf "%s\n" "$PATH"' bash "$env_file"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$guard/git" ]
  [[ "${lines[1]}" == "$guard:$TEST_DOTFILES/bin:"* ]]

  run env -u BASH_ENV -u ENV PATH="/usr/bin:/bin" /bin/bash -c \
    'source "$1"; printf "%s\n" "$PATH"' bash "$env_file"
  [ "$status" -eq 0 ]
  [[ "$output" == "$TEST_DOTFILES/bin:"* ]]
}

@test "session-endpoint-path: rejects a symlink and still replies with legacy JSON" {
  local env_file="$TEST_HOME/claude-session.env"
  local sentinel="$TEST_HOME/sentinel"
  mkdir -p "$TEST_DOTFILES/bin"
  printf '%s\n' unchanged >"$sentinel"
  ln -s "$sentinel" "$env_file"
  run --separate-stderr env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    CLAUDE_ENV_FILE="$env_file" /bin/bash -c \
    'printf "%s\n" '"'"'{"hook_event_name":"SessionStart"}'"'"' | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.env.PATH | length > 0'
  [ "$(cat "$sentinel")" = unchanged ]
}

@test "session-endpoint-path: prepends fnm node bin when .node-version present" {
  mkdir -p "$TEST_DOTFILES/bin" "$TEST_HOME/.local/share/fnm/node-versions/v22.22.0/installation/bin"
  echo "v22.22.0" > "$TEST_HOME/.node-version"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{}" | ./agent-hooks/session-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"node-versions/v22.22.0/installation/bin"* ]]
}

@test "prepend-endpoint-path: prepends fnm node bin for Shell tool" {
  mkdir -p "$TEST_DOTFILES/bin" "$TEST_HOME/.local/share/fnm/node-versions/v22.22.0/installation/bin"
  echo "v22.22.0" > "$TEST_HOME/.node-version"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{\"tool_name\": \"Shell\", \"tool_input\": {\"command\": \"command -v npx\"}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *"node-versions/v22.22.0/installation/bin"* ]]
}

@test "prepend-endpoint-path: prepends dotfiles/bin for Task tool (subagent shell)" {
  mkdir -p "$TEST_DOTFILES/bin"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" bash -c 'echo "{\"tool_name\": \"Task\", \"tool_input\": {\"command\": \"command -v jq\"}}" | ./agent-hooks/prepend-endpoint-path.sh'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permission"'* ]]
  [[ "$output" == *'"allow"'* ]]
  [[ "$output" == *"updated_input"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin"* ]]
}

@test "prepend-endpoint-path: rewrites hardcoded /usr/bin/curl to shim" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload
  payload='{"tool_name":"Shell","tool_input":{"command":"/usr/bin/curl --version"}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'echo "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated_input"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin/curl --version"* ]]
  [[ "$output" != *"/usr/bin/curl"* ]]
}

@test "prepend-endpoint-path: rewrites /usr/bin/curl even when PATH already prepended" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload
  payload="{\"tool_name\":\"Shell\",\"tool_input\":{\"command\":\"export PATH=\\\"$TEST_DOTFILES/bin:/usr/bin:/bin\\\"; /usr/bin/curl -I https://example.com\"}}"
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'echo "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updated_input"* ]]
  [[ "$output" == *"$TEST_DOTFILES/bin/curl"* ]]
  [[ "$output" != *"/usr/bin/curl"* ]]
}

assert_explicit_python_unchanged() {
  local host="$1" command="$2" payload
  mkdir -p "$TEST_DOTFILES/bin"
  payload=$(jq -nc --arg host "$host" --arg command "$command" '
    {tool_name:"Bash",tool_input:{command:$command}}
    + (if $host == "codex" then {turn_id:"turn-example"}
       elif $host == "claude" then {permission_mode:"default",hook_event_name:"PreToolUse",transcript_path:"/tmp/fixture.jsonl"}
       else {} end)')
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg command "$command" --arg prefix "$TEST_DOTFILES/bin" '
    (.hookSpecificOutput.updatedInput.command // .updated_input.command)
    | startswith("PATH=") and contains($prefix) and endswith("; " + $command)'
}

@test "prepend-endpoint-path: preserves an explicit Apple python3 command" {
  assert_explicit_python_unchanged legacy '/usr/bin/python3 -I -S -V'
}

@test "prepend-endpoint-path: preserves an explicit Apple python3.13 command" {
  assert_explicit_python_unchanged codex '/usr/bin/python3.13 -I -S -V'
}

@test "prepend-endpoint-path: preserves Python paths in an agent draft" {
  local command
  command=$(cat <<'COMMAND'
cat <<'DRAFT'
The reported paths are /usr/bin/python3 and "/usr/bin/python3.13".
DRAFT
COMMAND
)
  assert_explicit_python_unchanged claude "$command"
}

@test "prepend-endpoint-path: parses hook JSON without Python" {
  grep -q '/usr/bin/plutil' agent-hooks/prepend-endpoint-path.sh
  ! grep -vE '^[[:space:]]*#' agent-hooks/prepend-endpoint-path.sh \
    | grep -qE '(^|[[:space:]])python3([[:space:]]|$)'
}

@test "prepend-endpoint-path: Codex Bash input uses native updatedInput response" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload='{"turn_id":"turn-example","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"echo ready"}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg prefix "$TEST_DOTFILES/bin" '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    .hookSpecificOutput.permissionDecision == "allow" and
    (.hookSpecificOutput.updatedInput.command | contains($prefix) and contains("echo ready")) and
    (has("updated_input") | not)'
}

@test "prepend-endpoint-path: Codex non-shell input returns native allow without an update" {
  local payload='{"turn_id":"turn-example","hook_event_name":"PreToolUse","tool_name":"apply_patch","tool_input":{}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    .hookSpecificOutput.permissionDecision == "allow" and
    (.hookSpecificOutput | has("updatedInput") | not)'
}

@test "prepend-endpoint-path: Claude keeps the native tool arguments and existing approval rules" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload='{"hook_event_name":"PreToolUse","permission_mode":"default","transcript_path":"/tmp/fixture.jsonl","tool_name":"Bash","tool_input":{"command":"echo ready","description":"Print a fixture","timeout":4000}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg prefix "$TEST_DOTFILES/bin" '
    .hookSpecificOutput.hookEventName == "PreToolUse" and
    (.hookSpecificOutput | has("permissionDecision") | not) and
    (.hookSpecificOutput.updatedInput.command | contains($prefix) and contains("echo ready")) and
    .hookSpecificOutput.updatedInput.description == "Print a fixture" and
    .hookSpecificOutput.updatedInput.timeout == 4000 and
    (has("updated_input") | not)'
}

@test "prepend-endpoint-path: Claude no-op makes no approval decision" {
  local payload='{"hook_event_name":"PreToolUse","permission_mode":"default","transcript_path":"/tmp/fixture.jsonl","tool_name":"Read","tool_input":{}}'
  run bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '. == {}'
}

@test "prepend-endpoint-path: Claude auto mode makes no path or approval decision" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload='{"hook_event_name":"PreToolUse","permission_mode":"auto","transcript_path":"/tmp/fixture.jsonl","tool_name":"Bash","tool_input":{"command":"echo ready"}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '. == {}'
}

@test "prepend-endpoint-path: preserves approved Bash input in Claude permission modes" {
  mkdir -p "$TEST_DOTFILES/bin"
  local mode payload
  for mode in acceptEdits dontAsk bypassPermissions; do
    payload="$(jq -cn --arg mode "$mode" '{
      hook_event_name: "PreToolUse",
      permission_mode: $mode,
      transcript_path: "/tmp/fixture.jsonl",
      tool_name: "Bash",
      tool_input: {command: "pwd", description: "Read fixture root"}
    }')"
    run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
      bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
    [ "$status" -eq 0 ]
    printf '%s' "$output" | jq -e '. == {}'
  done
}

@test "prepend-endpoint-path: keeps explicit shim rewrites in Claude permission modes" {
  mkdir -p "$TEST_DOTFILES/bin"
  local payload='{"hook_event_name":"PreToolUse","permission_mode":"dontAsk","transcript_path":"/tmp/fixture.jsonl","tool_name":"Bash","tool_input":{"command":"/usr/bin/curl --version","description":"Read fixture version"}}'
  run env -u BASH_ENV -u ENV DOTFILES_DIR="$TEST_DOTFILES" HOME="$TEST_HOME" \
    bash -c 'printf "%s\n" "$1" | ./agent-hooks/prepend-endpoint-path.sh' bash "$payload"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e --arg command "$TEST_DOTFILES/bin/curl --version" \
    '.hookSpecificOutput | (.updatedInput.command == $command) and
     (.updatedInput.description == "Read fixture version") and (has("permissionDecision") | not)'
}

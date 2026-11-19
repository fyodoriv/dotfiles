#!/usr/bin/env bats

load test_helper

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

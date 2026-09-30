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

@test "prepend-endpoint-path: parses hook JSON without Python" {
  grep -q '/usr/bin/plutil' agent-hooks/prepend-endpoint-path.sh
  ! grep -vE '^[[:space:]]*#' agent-hooks/prepend-endpoint-path.sh \
    | grep -qE '(^|[[:space:]])python3([[:space:]]|$)'
}

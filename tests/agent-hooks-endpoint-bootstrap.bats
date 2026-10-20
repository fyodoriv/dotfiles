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

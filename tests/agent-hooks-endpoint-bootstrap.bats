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

# Same rule as the doctor check security.hooks_use_bootstrap, run on CI so a
# new hook cannot pass the PR and then fail the doctor after apply.
@test "every agent hook that calls endpoint tools sources the PATH bootstrap" {
  bad=""
  for f in agent-hooks/*; do
    [ -f "$f" ] || continue
    case "$f" in
      *bootstrap-endpoint-path.sh|*with-endpoint-path.sh|*prepend-endpoint-path.sh|*session-endpoint-path.sh) continue ;;
    esac
    case "$f" in *.sh) ;; *) [ -x "$f" ] || continue ;; esac
    head -1 "$f" | grep -q '^#!' || continue
    grep -qE 'bootstrap-endpoint-path|with-endpoint-path|prepend-endpoint-path|dotfiles_prepend_endpoint_tool_paths' "$f" && continue
    grep -qE '\bjq\b|\bggrep\b|\bgrep\b|\bfind\b|\bcurl\b|\bawk\b|\bsed\b|\bpython3\b|\bnpx\b|\bnode\b' "$f" || continue
    bad="$bad $f"
  done
  echo "hooks without the bootstrap:$bad"
  [ -z "$bad" ]
}

#!/usr/bin/env bats
# PreToolUse Bash hook: dotfiles tests run on hosted CI only, never locally.

HOOK="$BATS_TEST_DIRNAME/../agent-hooks/block-local-tests.sh"

setup() {
  # A fake dotfiles checkout (the two marker files) and a plain repo.
  CHECKOUT="$BATS_TEST_TMPDIR/dotfiles"
  OTHER="$BATS_TEST_TMPDIR/other"
  mkdir -p "$CHECKOUT/agent-hooks" "$CHECKOUT/bin" "$CHECKOUT/sub" "$OTHER"
  : > "$CHECKOUT/agent-hooks/require-heavy-run.sh"
  : > "$CHECKOUT/bin/dotfiles-doctor"
}

run_hook() {
  local json
  json="$(jq -cn --arg c "$1" --arg d "${2:-$CHECKOUT}" '{tool_input:{command:$c},cwd:$d}')"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$json" "$HOOK"
}

@test "blocks local test runs in a dotfiles checkout, with the CI message" {
  for c in "make check" "make test" "make test-all" "make test-force" "make e2e" \
           "bats tests/x.bats" "bats tests/" "bats -f foo tests/x.bats" \
           "bin/bats-affected origin/feat/chezmoi" \
           "heavy-run make test-all" "heavy-run --exclusive bats tests/x.bats" \
           "time nice -n 5 make check" "env CI=1 make check" "FOO=1 make check" \
           "make lint && make check" "make lint; bats tests/x.bats" \
           "cd sub && bats ../tests/x.bats" "bash -c 'make check'" \
           "make check | tail -5" "echo go && (make test-all)"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
    [[ "$output" == *"tests run on CI only"* ]] || { echo "no message: $c"; return 1; }
    [[ "$output" == *"gh pr checks"* ]] || { echo "no CI hint: $c"; return 1; }
  done
}

@test "blocks tests started through xargs, find -exec, npx and eval" {
  for c in "ls tests | xargs bats" "xargs -a list bats" "xargs -n1 -I{} make test-all" \
           "find . -exec bats {} +" "find . -name x -execdir make check \\;" \
           "npx bats tests/x.bats" "eval make check" "eval 'make check'" "eval \"bats tests/x.bats\""; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "allows xargs and find -exec that start other commands" {
  for c in "ls | xargs rg bats" "find . -exec rg bats {} +" "echo 'make check' | xargs echo" \
           "xargs -n1 shellcheck"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c: $output"; return 1; }
  done
}

# Documented gaps (docs/agent-hooks.md): the hook is a guardrail, not a
# security boundary. These pass on purpose; if one starts to block, update the doc.
@test "known gaps: a command name built at run time and a script piped to a shell pass" {
  for c in 'x=$(which bats); $x tests/x.bats' 'echo make check | sh' '$(which bats) tests/x.bats'; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "now blocked (update docs/agent-hooks.md): $c"; return 1; }
  done
}

@test "allows lint, shellcheck and read-only commands in a dotfiles checkout" {
  for c in "make lint" "make lint-tasks" "make lint-full" "shellcheck bin/dotfiles" \
           "bash -n bin/dotfiles" "rg bats tests" "rg -n 'make check' docs" \
           "git status" "git commit -m 'run make check and bats tests/x.bats'" \
           "bats --version" "make -n check" "make --dry-run test-all" \
           "gh pr checks 12 --repo fyodoriv/dotfiles" "cat tests/x.bats" \
           "echo 'make check'" "sed -n 1,5p Makefile"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c: $output"; return 1; }
  done
}

@test "allows the same test commands in a repo that is not dotfiles" {
  for c in "make check" "make test-all" "bats tests/x.bats" "heavy-run make e2e"; do
    run_hook "$c" "$OTHER"
    [ "$status" -eq 0 ] || { echo "blocked: $c: $output"; return 1; }
  done
}

@test "blocks a command that moves into a dotfiles checkout from elsewhere" {
  for c in "cd $CHECKOUT && make check" "make -C $CHECKOUT test-all" \
           "cd \"$CHECKOUT\" && bats tests/x.bats"; do
    run_hook "$c" "$OTHER"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "a subfolder of a checkout counts as the checkout" {
  run_hook "make check" "$CHECKOUT/sub"
  [ "$status" -eq 2 ]
}

@test "the human escape hatch turns the hook off; text in the command does not" {
  run bash -c 'jq -cn --arg c "make check" --arg d "$1" "{tool_input:{command:\$c},cwd:\$d}" | DOTFILES_ALLOW_LOCAL_TESTS=1 bash "$2"' _ "$CHECKOUT" "$HOOK"
  [ "$status" -eq 0 ]
  run_hook "DOTFILES_ALLOW_LOCAL_TESTS=1 make check"
  [ "$status" -eq 2 ]
}

@test "empty or malformed input is allowed" {
  run bash -c 'printf "" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  run bash -c 'printf "not json" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
}

@test "the hook is wired in the Agentfile and linked by apply" {
  grep -q 'hooks/block-local-tests.sh' "$BATS_TEST_DIRNAME/../Agentfile.yaml"
  grep -q 'block-local-tests.sh' "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_agent-hooks.sh"
  grep -q '^hook-block-local-tests' "$BATS_TEST_DIRNAME/../config/perf-budget.tsv"
}

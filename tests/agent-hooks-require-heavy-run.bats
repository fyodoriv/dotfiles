#!/usr/bin/env bats
# PreToolUse Bash hook: full test suites and builds must run through heavy-run (#357).

HOOK="./agent-hooks/require-heavy-run.sh"

run_hook() {
  local json
  json="$(jq -cn --arg c "$1" '{tool_input:{command:$c}}')"
  run bash -c 'printf "%s" "$1" | '"$HOOK" _ "$json"
}

@test "blocks unwrapped full runs with the fix-it message" {
  for c in "yarn test:coverage" "npm test" "npm run test" "npm run test:all" "pnpm test" \
           "npx vitest run" "vitest run" "npx jest" "jest" "npx playwright test" \
           "yarn build" "npm run build" "npm run -s build" "bats tests" "bats tests/" \
           "cd app && yarn test" "FOO=1 npm test" "yarn build && yarn lint && yarn test:coverage"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
    [[ "$output" == *'Run this as `heavy-run <command>`.'* ]] || { echo "no message: $c"; return 1; }
  done
}

@test "allows wrapped runs and single-file runs" {
  for c in "heavy-run yarn test:coverage" "heavy-run npm run build" "npx vitest run one.test.ts" \
           "npx vitest run src/a/b.test.ts" "npx jest src/x.test.js" "bats tests/foo.bats" \
           "bats -f 'x' tests/foo.bats" "git status" "echo npm test" "rg 'yarn build' docs" \
           "cd app && heavy-run yarn test" "npm install" "npm run lint"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c ($output)"; return 1; }
  done
}

@test "HEAVY_RUN_HOOK=off turns the hook off" {
  json='{"tool_input":{"command":"npm test"}}'
  run env HEAVY_RUN_HOOK=off bash -c 'printf "%s" "$1" | '"$HOOK" _ "$json"
  [ "$status" -eq 0 ]
}

@test "empty or non-Bash input passes" {
  run bash -c "printf '{}' | $HOOK"
  [ "$status" -eq 0 ]
}

@test "the hook is wired in the Agentfile and installed by the agent-hooks script" {
  grep -q 'require-heavy-run.sh' Agentfile.yaml
  grep -q 'require-heavy-run.sh' .chezmoiscripts/run_after_agent-hooks.sh
}

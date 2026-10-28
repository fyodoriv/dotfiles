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

@test "blocks other headless-browser entry points (e2e, ui, exec playwright, make e2e)" {
  for c in "npm run e2e" "npm run e2e:ci" "yarn e2e" "npm run ui" "pnpm ui:audit" \
           "pnpm exec playwright test" "yarn playwright test" "npm exec playwright test" \
           "npx playwright test --ui" "make e2e" "make test-all" "cd app && npm run ui" \
           "make test-force" "pnpm --filter web e2e" "pnpm -F web run e2e" "pnpm dlx playwright test" "bunx playwright test"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "blocks fake one-test forms and prefixed runs" {
  for c in "npx playwright test -g ." "npx playwright test --config a/b.ts" "pnpm ui -g ''" \
           "npm run e2e -- --grep=." "pnpm e2e ." "pnpm e2e tests/" \
           "npm run e2e -- --config playwright.config.ts" "playwright test -g '.*'" \
           "time make e2e" "timeout 600 make e2e" "env CI=1 make e2e" "nice -n 5 make e2e" \
           "nohup make test-all" "caffeinate -i make e2e" "command make e2e" "exec make e2e" \
           "time nice -n 5 npm run ui"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "allows quoted text, heredoc bodies, and prefixed wrapped runs" {
  for c in 'git commit -m "fix; make e2e now"' 'gh pr create --body "npm ci && make e2e"' \
           "echo 'make e2e && npm test'" "printf 'make test-all\\n'" "time heavy-run make e2e" \
           "nice -n 5 heavy-run npm run ui" "timeout 600 heavy-run make e2e" "pnpm ui -g 'login flow'"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c ($output)"; return 1; }
  done
  run_hook $'cat > notes.md <<\'EOF\'\nmake e2e\nnpm test\nEOF\ngit status'
  [ "$status" -eq 0 ] || { echo "blocked heredoc ($output)"; return 1; }
  run_hook $'git commit -q -F - <<EOF\nfix: x\n\nmake e2e\nEOF'
  [ "$status" -eq 0 ] || { echo "blocked heredoc2 ($output)"; return 1; }
  run_hook $'cat <<\'EOF\'\nhi\nEOF\nmake e2e'
  [ "$status" -eq 2 ] || { echo "heredoc hid a real run"; return 1; }
}

@test "allows wrapped runs and single-file runs" {
  for c in "heavy-run yarn test:coverage" "heavy-run npm run build" "npx vitest run one.test.ts" \
           "npx vitest run src/a/b.test.ts" "npx jest src/x.test.js" "bats tests/foo.bats" \
           "bats -f 'x' tests/foo.bats" "git status" "echo npm test" "rg 'yarn build' docs" \
           "cd app && heavy-run yarn test" "npm install" "npm run lint" \
           "pnpm ui -g login" "pnpm ui tests/one.spec.ts" "npm run e2e -- --grep=login" "npx playwright test -g login" \
           "npx playwright test tests/a.spec.ts" "make -n e2e" "make --dry-run test-all" "pnpm exec playwright test -g x" \
           "heavy-run npm run ui" "heavy-run make e2e" "pnpm exec playwright install" "make lint"; do
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

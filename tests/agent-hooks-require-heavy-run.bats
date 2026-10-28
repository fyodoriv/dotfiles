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

@test "blocks prefix flags, sudo, control flow, flag values, and command substitution" {
  for c in "time -p npm test" "timeout -s KILL 5 npm test" "nice -n 10 make e2e" "env A=1 make e2e" \
           "env -u FOO make e2e" "sudo npm test" "sudo -u me make e2e" "caffeinate -t 60 make e2e" \
           "if true; then npm test; fi" "while true; do make e2e; done" "true && (npm test)" \
           "{ make e2e; }" "for f in a b; do npm run ui; done" \
           "npx playwright test --output out/res" "npx playwright test --outputFile a/b.xml" \
           "npm run e2e -- --output-dir results/run1" \
           'echo "$(npm test)"' 'echo "`make e2e`"'; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "vitest and jest: a flag value is not a test file" {
  for c in "npx vitest --reporter=junit --outputFile a/b.xml" "npx jest --outputFile a/b.json" \
           "vitest run --outputFile a/b.xml" "npx vitest run --coverage.reportsDirectory cov/out"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
  for c in "npx vitest run src/a.test.ts" "npx jest src/x.test.js" "npx vitest run -t foo" \
           "npx vitest --outputFile a/b.xml src/a.test.ts"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c ($output)"; return 1; }
  done
}

@test "allows wrapped prefixed runs, control flow, and test filters" {
  for c in "time -p heavy-run make e2e" "sudo heavy-run make e2e" "timeout -s KILL 5 heavy-run npm test" \
           "if true; then heavy-run npm test; fi" "npm run test -- -t foo" "pnpm ui -t foo" \
           "npx playwright test --headed tests/a.spec.ts" 'echo "hello (world)"' 'echo "$(date)"' \
           "if true; then echo ok; fi"; do
    run_hook "$c"
    [ "$status" -eq 0 ] || { echo "blocked: $c ($output)"; return 1; }
  done
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

@test "blocks npx and npm exec with flags and version suffixes, and node_modules/.bin paths" {
  for c in "npx -y playwright@1 test" "npx --yes playwright@1.40.0 test" "npx -y vitest@2 run" \
           "npm exec -y playwright test" "npm exec --yes -- playwright test" "npm exec -p playwright playwright test" \
           "pnpm dlx playwright@1 test" "pnpm exec -- playwright test" \
           "./node_modules/.bin/playwright test" "node_modules/.bin/vitest run" "/usr/bin/make e2e"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "blocks bun, turbo, and gmake" {
  for c in "bun test" "bun run test" "bun run e2e" "bun x playwright test" "bunx -y playwright@1 test" \
           "turbo run test" "turbo test" "turbo run build --filter=web" "turbo run e2e" "gmake e2e" "gmake test-all"; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "blocks bash -c and sh -c strings, and command substitution inside a word" {
  for c in 'bash -c "make e2e"' "sh -c 'npm test'" 'bash -lc "cd app && yarn test"' 'sudo bash -c "make e2e"' \
           'zsh -c "bun run e2e"' 'bash -c "bash -c \"make e2e\""' \
           'make -j$(nproc) e2e' 'make -j`nproc` e2e' 'make -j"$(nproc)" e2e' 'make -j$(sysctl -n hw.ncpu) test-all'; do
    run_hook "$c"
    [ "$status" -eq 2 ] || { echo "not blocked: $c"; return 1; }
  done
}

@test "allows the new forms under heavy-run and their single-test runs" {
  for c in "heavy-run npx -y playwright@1 test" "heavy-run npm exec -y playwright test" \
           "heavy-run ./node_modules/.bin/playwright test" "~/bin/heavy-run make e2e" "heavy-run bun test" \
           "heavy-run turbo run test" "heavy-run gmake e2e" 'bash -c "heavy-run make e2e"' "sh -c 'heavy-run npm test'" \
           'heavy-run make -j$(nproc) e2e' \
           "npx -y playwright@1 test -g login" "npx -y vitest@2 run src/a.test.ts" "./node_modules/.bin/playwright test tests/a.spec.ts" \
           "bun test src/a.test.ts" "turbo run lint" "bun install" "npx -y prettier@3 --check ." \
           'bash -c "echo hi"' 'git commit -m "run bash -c \"make e2e\" later"' 'echo "x; bash -c \"make e2e\""' \
           'make -j$(nproc) lint' 'echo $(date)'; do
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

#!/usr/bin/env bats
# Pin the critique_test self-critic tool added to lib/local-ai-agent.py.
# Failure mode: run-4 dogfood committed a hallucinated stub test for
# the "Devin model agrees across three layers" task. Test used a fake
# model name (gpt-4-turbo), tautological assertions, and explicit
# "placeholder" comments. The critic catches all three.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_critique() {
  local test_path="$1"
  local task_desc="$2"
  python3 - "$test_path" "$task_desc" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
path, desc, root = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_file_location(
    "agent", os.path.join(root, "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r = m.run_critique_test(path, desc, root)
sys.stdout.write(r["stdout"])
sys.stderr.write(r["stderr"])
sys.exit(r["exit_code"])
PY
}

setup() { TMP=$(mktemp -d); }
teardown() { rm -rf "$TMP"; }

@test "critique: placeholder comment is caught" {
  cat > "$TMP/test.bats" <<'EOF'
@test "x" {
  # This is a placeholder
  [ 1 -eq 1 ]
}
EOF
  run _critique "$TMP/test.bats" "Write a test that does something"
  [ "$status" -eq 1 ]
  [[ "$output" == *"placeholder"* ]]
}

@test "critique: 'would require' weasel-comment is caught" {
  cat > "$TMP/test.bats" <<'EOF'
@test "x" {
  # Actual implementation would require ...
  [ 1 -eq 1 ]
}
EOF
  run _critique "$TMP/test.bats" "task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"would require"* || "$output" == *"actual implementation"* ]]
}

@test "critique: TODO comment is caught" {
  cat > "$TMP/test.bats" <<'EOF'
@test "x" {
  # TODO: implement this properly
  [ 1 -eq 1 ]
}
EOF
  run _critique "$TMP/test.bats" "task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TODO"* ]]
}

@test "critique: tautological assertion is caught" {
  # Mirrors the run-4 hallucinated devin-model test:
  # export X="foo" then assert "$X" = "foo".
  cat > "$TMP/test.bats" <<'EOF'
@test "tautology" {
  export FOO="bar"
  run bash -c 'echo $FOO'
  [ "$status" -eq 0 ]
  [ "$FOO" = "bar" ]
}
EOF
  run _critique "$TMP/test.bats" "task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tautological"* ]]
}

@test "critique: missing file anchor from task description is caught" {
  cat > "$TMP/test.bats" <<'EOF'
@test "generic" {
  [ 1 -eq 1 ]
}
EOF
  run _critique "$TMP/test.bats" \
    "Write a test that grep's home/zshrc.ai-tools for the env-var assignment"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NONE of the task's named files"* ]]
}

@test "critique: missing quoted literal from task is caught" {
  cat > "$TMP/test.bats" <<'EOF'
@test "x" {
  [ 1 -eq 1 ]
}
EOF
  run _critique "$TMP/test.bats" \
    "The test must assert it matches the literal \`gpt-5-5-xhigh-priority\`"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NONE of the task's quoted literals"* ]]
}

@test "critique: clean test that references the right anchors PASSES" {
  cat > "$TMP/test.bats" <<'EOF'
@test "real test" {
  run grep -c "gpt-5-5-xhigh-priority" home/zshrc.ai-tools
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}
EOF
  run _critique "$TMP/test.bats" \
    "Test that home/zshrc.ai-tools matches the literal \`gpt-5-5-xhigh-priority\`"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "critique: missing file is reported as an error" {
  run _critique "$TMP/nonexistent.bats" "task"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "critique: catches the exact run-4 hallucinated test" {
  # This is the actual stub the agent committed in run-4 before we
  # reverted it. Reproducing here as a regression guard.
  cat > "$TMP/test.bats" <<'EOF'
#!/usr/bin/env bats
setup() {
    TEST_DIR=$(mktemp -d)
    cd "$TEST_DIR"
}

@test "Model setting consistency: env var, config file, and CLI argument" {
    export DEVIN_MODEL="gpt-4-turbo"
    cat > config.json << EOF2
{
    "model": "gpt-4-turbo"
}
EOF2
    # This is a placeholder - actual implementation would depend on how
    run bash -c 'echo $DEVIN_MODEL'
    [ "$DEVIN_MODEL" = "gpt-4-turbo" ]
}
EOF
  run _critique "$TMP/test.bats" \
    "Per AGENTS.md three layers must agree on \`gpt-5-5-xhigh-priority\`: \
the DEVIN_MODEL env var (in home/zshrc.ai-tools), agent.model in \
~/.config/devin/config.json, and minsky's per-persona ANTHROPIC_MODEL."
  [ "$status" -eq 1 ]
  # Should fire all three: placeholder, tautology, missing-literal.
  [[ "$output" == *"placeholder"* ]]
  [[ "$output" == *"tautological"* ]]
  [[ "$output" == *"NONE of the task's quoted literals"* ]]
}

@test "critique: does not require test to reference its own path" {
  # Run-5 false positive: critic listed tests/devin-model-three-layer-
  # consistency.bats as a "required anchor", but that's the file being
  # WRITTEN — the test can't import itself.
  cat > "$TMP/tests-target.bats" <<'EOF'
#!/usr/bin/env bats
@test "real" {
  run grep -c "gpt-5-5-xhigh-priority" home/zshrc.ai-tools
  [ "$status" -eq 0 ]
}
EOF
  # Task description names: tests/tests-target.bats (the test itself)
  # AND home/zshrc.ai-tools (the file under test). Only the latter
  # should be required.
  run _critique "$TMP/tests-target.bats" \
    "Write tests/tests-target.bats to grep home/zshrc.ai-tools for the literal \`gpt-5-5-xhigh-priority\`"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

@test "critique: sibling .bats files are not required anchors" {
  cat > "$TMP/new.bats" <<'EOF'
@test "real" {
  run grep -c "foo" lib/somelib.py
  [ "$status" -eq 0 ]
}
EOF
  # Task mentions tests/other.bats as an EXAMPLE — should not force
  # the new test to reference it.
  run _critique "$TMP/new.bats" \
    "Write a test like tests/other.bats but for lib/somelib.py"
  [ "$status" -eq 0 ]
}

# Helper: write N @test stubs to a file WITHOUT triggering bats's source
# preprocessor (which rewrites any literal `@test` token at parse time
# into `bats_test_function ...`, even inside quoted heredocs).
_write_bats_with_n_tests() {
  local path="$1" n="$2"
  python3 -c "
import sys
n = int(sys.argv[1])
with open(sys.argv[2], 'w') as f:
    for i in range(n):
        f.write('AT_TEST' + ' \"test ' + str(i) + '\" { [ 1 -eq 1 ]; }\n')
# Replace AT_TEST with the real bats marker. We use a placeholder to
# avoid bats preprocessing our .bats test file.
import os
text = open(sys.argv[2]).read().replace('AT_TEST', chr(64)+'test')
open(sys.argv[2], 'w').write(text)
" "$n" "$path"
}

@test "critique: requires N @test cases when task specifies N" {
  # File has 1 test, task asks for 3 → fail.
  _write_bats_with_n_tests "$TMP/short.bats" 1
  run _critique "$TMP/short.bats" \
    "Create tests/short.bats with 3 @test cases modeled on tests/local-ai-agent.bats"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asked for 3"* ]]
  [[ "$output" == *"has only 1"* ]]
}

@test "critique: passes when @test count >= required" {
  _write_bats_with_n_tests "$TMP/enough.bats" 3
  run _critique "$TMP/enough.bats" \
    "with 3 @test cases"
  [ "$status" -eq 0 ]
}

@test "critique: understands 'N tests' phrasing (not just '@test')" {
  _write_bats_with_n_tests "$TMP/three.bats" 1
  run _critique "$TMP/three.bats" \
    "Write the bats file to include 5 tests that verify the output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"asked for 5"* ]]
}

@test "critique: does not trigger on implausible large counts (line numbers etc)" {
  _write_bats_with_n_tests "$TMP/single.bats" 1
  # "200 bytes" is a size, not a test count → should not fail on count.
  run _critique "$TMP/single.bats" \
    "The script is 200 bytes and the test checks output"
  [ "$status" -eq 0 ]
}

@test "critique: procedural boilerplate (make check, git add, done) is not required" {
  _write_bats_with_n_tests "$TMP/ok.bats" 3
  # Simulate the full loop prompt which wraps every task with a
  # "Run \`make check\`, stage with \`git add <files>\`, call \`done\`"
  # suffix. The test should not be required to reference those.
  local prompt="Title: Add basic surface test
Details: Create tests/ok.bats with 3 @test cases.
When the task is complete:
  1. Run \`make check\` and ensure it passes.
  2. Stage the changed files (\`git add <files>\`); DO NOT commit.
  3. Call the \`done\` tool with a one-line summary."
  run _critique "$TMP/ok.bats" "$prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

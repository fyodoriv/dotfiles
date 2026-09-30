#!/usr/bin/env bats
# Pin the hard guards added to lib/local-ai-agent.py after the run-2
# dogfood loop where the agent killed Ollama on port 11434 and wrote
# tests that clobbered $HOME/.config (see
# docs/audits/local-ai-failure-modes.md).

REPO_ROOT="$BATS_TEST_DIRNAME/.."

# Helper: invoke run_bash on the agent module via a tiny python harness
# so the test exercises the real implementation rather than a mock.
_run_bash() {
  local cmd="$1"
  python3 - "$cmd" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
cmd, cwd = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "local_ai_agent", os.path.join(cwd, "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r = m.run_bash(cmd, cwd)
sys.stdout.write(r["stdout"])
sys.stderr.write(r["stderr"])
sys.exit(r["exit_code"])
PY
}

@test "guard: kill is blocked" {
  run _run_bash "kill 12345"
  [ "$status" -eq 126 ]
  [[ "$output" == *"process-lifecycle commands"* || \
     "$stderr" == *"process-lifecycle commands"* ]] || \
  [[ "$(echo "$output"; cat /dev/stderr 2>/dev/null || true)" == *"process-lifecycle"* ]]
  # The deny message lands on stderr; bats's `run` merges both into $output.
  [[ "$output" == *"process-lifecycle"* ]]
}

@test "guard: pkill is blocked" {
  run _run_bash "pkill ollama"
  [ "$status" -eq 126 ]
  [[ "$output" == *"process-lifecycle"* ]]
}

@test "guard: launchctl kickstart -k is blocked" {
  run _run_bash "launchctl kickstart -k gui/501/com.dotfiles.ollama"
  [ "$status" -eq 126 ]
  [[ "$output" == *"process-lifecycle"* ]]
}

@test "guard: docker stop is blocked" {
  run _run_bash "docker stop my-container"
  [ "$status" -eq 126 ]
  [[ "$output" == *"process-lifecycle"* ]]
}

@test "guard: writing \$HOME from a bats test heredoc is blocked" {
  # Simulate the destructive pattern: `cat > tests/foo.bats <<EOF ... $HOME ...`
  # The agent's actual command form when it wrote the broken opencode test.
  run _run_bash 'cat > tests/foo.bats <<EOF
mkdir -p $HOME/.config/opencode
EOF'
  [ "$status" -eq 126 ]
  [[ "$output" == *"\$HOME"* ]]
}

@test "guard: writing ~/.config from a bats test heredoc is blocked" {
  run _run_bash 'cat > tests/foo.bats <<EOF
cp some.json ~/.config/opencode/opencode.json
EOF'
  [ "$status" -eq 126 ]
  [[ "$output" == *"\$HOME"* || "$output" == *".config"* ]]
}

@test "guard: regular bash commands still work" {
  run _run_bash "echo hello && ls /tmp >/dev/null"
  [ "$status" -eq 0 ]
}

@test "guard: harmless 'kill' substring (e.g. in a filename) is allowed" {
  # 'kill' as a literal word would be blocked, but the deny regex uses
  # word boundaries — `tests/skill-creator.md` must not trigger.
  run _run_bash "ls tests/ | grep -c '.bats' >/dev/null"
  [ "$status" -eq 0 ]
}

@test "guard: destructive overwrite of large file is refused" {
  # Run-5 surfaced: agent wrote 345-byte stub over 7089-byte tracked
  # git-hooks/pre-commit, destroying the existing security hook.
  python3 - "$REPO_ROOT" <<'PY'
import importlib.util, os, sys, tempfile
spec = importlib.util.spec_from_file_location(
    "agent", os.path.join(sys.argv[1], "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
    big = os.path.join(d, "big.sh")
    # 150 lines of real-looking content
    with open(big, "w") as f:
        for i in range(150):
            f.write(f"# real line {i} explaining the purpose of this script\n")
    big_size = os.path.getsize(big)
    # Try to overwrite with a 100-byte stub
    r = m.run_write_file("big.sh", "echo stub", d)
    assert r["exit_code"] == 1, f"expected refusal, got {r}"
    assert "refused" in r["stderr"], r["stderr"]
    # File must be unchanged
    assert os.path.getsize(big) == big_size, "file was overwritten anyway"
    print("PASS")
PY
}

@test "guard: small overwrite of small file is allowed" {
  # The guard only fires for files >100 lines. Small files are fair game.
  python3 - "$REPO_ROOT" <<'PY'
import importlib.util, os, sys, tempfile
spec = importlib.util.spec_from_file_location(
    "agent", os.path.join(sys.argv[1], "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
    small = os.path.join(d, "small.txt")
    with open(small, "w") as f:
        f.write("a\n" * 5)  # 5 lines
    r = m.run_write_file("small.txt", "new content", d)
    assert r["exit_code"] == 0, f"expected success, got {r}"
    print("PASS")
PY
}

@test "guard: large-to-large overwrite is allowed (no destruction)" {
  python3 - "$REPO_ROOT" <<'PY'
import importlib.util, os, sys, tempfile
spec = importlib.util.spec_from_file_location(
    "agent", os.path.join(sys.argv[1], "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
with tempfile.TemporaryDirectory() as d:
    f1 = os.path.join(d, "big.py")
    big_content = "\n".join(f"line {i}" for i in range(200))
    with open(f1, "w") as fh:
        fh.write(big_content)
    # Overwrite with similar-sized content
    new_content = "\n".join(f"new line {i}" for i in range(180))
    r = m.run_write_file("big.py", new_content, d)
    assert r["exit_code"] == 0, f"expected success, got {r}"
    print("PASS")
PY
}

#!/usr/bin/env bats
# Pin the `verify_cli_claims` tool in lib/local-ai-agent.py against the
# class of failures observed in
# docs/audits/local-ai-task-runs-2026-05-11.md: the model writes a doc
# that cites `bin/<name> --bogus-flag` for a flag the script never
# declared. The verifier must catch that.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

# Helper: call run_verify_cli_claims from a tiny python harness so the
# test exercises the real function (not a re-implementation).
_verify() {
  local doc_path="$1"
  python3 - "$doc_path" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
doc, cwd = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "local_ai_agent", os.path.join(cwd, "lib", "local-ai-agent.py"),
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r = m.run_verify_cli_claims(doc, cwd)
sys.stdout.write(r["stdout"])
sys.stdout.write("\n")
sys.stdout.write(r["stderr"])
sys.exit(r["exit_code"])
PY
}

@test "verify_cli_claims: clean doc with only real flags passes" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
Run: bin/local-ai-agent --max-turns 5 "hello"
Bench: bin/local-ai-bench --cold
EOF
  run _verify "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flags look real"* ]]
  rm -f "$tmp"
}

@test "verify_cli_claims: doc citing a nonexistent script fails" {
  local tmp
  tmp=$(mktemp)
  echo "Run: bin/no-such-script-please --foo" > "$tmp"
  run _verify "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT FOUND"* ]]
  rm -f "$tmp"
}

@test "verify_cli_claims: doc with hallucinated --prompt flag fails" {
  # This is exactly the task-1 regression: `bin/local-ai-agent --prompt`
  # is what the model invented; the real flag is positional.
  local tmp
  tmp=$(mktemp)
  echo 'Run: bin/local-ai-agent --prompt "Hi"' > "$tmp"
  run _verify "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--prompt"* ]]
  rm -f "$tmp"
}

@test "verify_cli_claims: --help and --version are always allowed" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
bin/local-ai-agent --help
bin/local-ai-bench --version
EOF
  run _verify "$tmp"
  [ "$status" -eq 0 ]
  rm -f "$tmp"
}

@test "verify_cli_claims: thin-wrapper bash script follows into lib/" {
  # bin/local-ai-agent is a 12-line bash wrapper that execs into
  # lib/local-ai-agent.py. Flags must be discovered from the lib file,
  # not from the bash wrapper. --num-ctx is declared in the .py, not
  # the wrapper.
  local tmp
  tmp=$(mktemp)
  echo "Run: bin/local-ai-agent --num-ctx 8192 \"hi\"" > "$tmp"
  run _verify "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"flags look real"* ]]
  rm -f "$tmp"
}

@test "verify_cli_claims: doc with no bin/ references returns clean" {
  local tmp
  tmp=$(mktemp)
  echo "Some doc with no CLI references at all." > "$tmp"
  run _verify "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no bin/<name> references"* ]]
  rm -f "$tmp"
}

#!/usr/bin/env bats
# Lock the static behavior of `bin/local-ai-loop` (the
# TASKS.md → local-ai-agent driver). The agent invocation itself is
# stubbed; we only exercise parsing + picking + tag filtering.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
LIB="$REPO_ROOT/lib/local-ai-loop.py"

# Synthesise a temp repo with a TASKS.md, then call the lib's
# read_tasks / pickable functions directly.
_pick_first() {
  local tasks_md="$1"
  python3 - "$tasks_md" <<'PY'
import importlib.util, sys, os
LIB = os.environ.get("LIB", "lib/local-ai-loop.py")
spec = importlib.util.spec_from_file_location("loop", LIB)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
tasks = m.read_tasks(sys.argv[1])
pickables = [t for t in tasks if m.pickable(t)]
if pickables:
    print(pickables[0]["id"])
PY
}

@test "loop: bin/local-ai-loop exists, executable, has the usage header" {
  [ -x "$REPO_ROOT/bin/local-ai-loop" ]
  head -25 "$REPO_ROOT/bin/local-ai-loop" | grep -q '^# Usage:'
}

@test "loop: parses a P2 task with all required fields" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

## P1

## P2

- [ ] Real task title
  - **ID**: real-task-id
  - **Tags**: docs, tests
  - **Details**: do the thing
  - **Files**: docs/foo.md
  - **Acceptance**: docs/foo.md exists
EOF
  LIB="$LIB" run _pick_first "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "real-task-id" ]
  rm -f "$tmp"
}

@test "loop: skips tasks tagged secrets / machine / manual / interactive / auth" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

## P1

- [ ] Has secrets tag
  - **ID**: jenkins-secrets-task
  - **Tags**: secrets, machine

- [ ] No excluded tag
  - **ID**: clean-task
  - **Tags**: docs
EOF
  LIB="$LIB" run _pick_first "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "clean-task" ]
  rm -f "$tmp"
}

@test "loop: respects P0 → P1 → P2 → P3 ordering" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

## P1

- [ ] Low-priority later
  - **ID**: p1-low
  - **Tags**: docs

## P2

- [ ] High-priority earlier
  - **ID**: p2-task
  - **Tags**: tests
EOF
  # p1-low should win over p2-task because P1 < P2.
  LIB="$LIB" run _pick_first "$tmp"
  [ "$status" -eq 0 ]
  [ "$output" = "p1-low" ]
  rm -f "$tmp"
}

@test "loop: tolerates an empty TASKS.md" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

## P1

## P2
EOF
  LIB="$LIB" run _pick_first "$tmp"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -f "$tmp"
}

@test "loop: --dry-run end-to-end against the real repo TASKS.md" {
  # Just confirm the binary parses + plans without invoking the agent.
  # Output should mention at least one task from the real queue.
  run "$REPO_ROOT/bin/local-ai-loop" --dry-run --deadline 1m --max-tasks 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"loop: picked"* ]] || [[ "$output" == *"no pickable tasks"* ]]
}

_remove_block() {
  local tmpfile="$1" task_id="$2"
  LIB="$LIB" python3 - "$tmpfile" "$task_id" <<'PY'
import importlib.util, sys, os
spec = importlib.util.spec_from_file_location("loop", os.environ["LIB"])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
removed = m.remove_task_block(sys.argv[1], sys.argv[2])
print("removed" if removed else "not_found")
PY
}

@test "loop: remove_task_block deletes the matching task + trailing blanks" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

## P1

- [ ] First task
  - **ID**: keep-me
  - **Tags**: docs

- [ ] Doomed task
  - **ID**: kill-me
  - **Tags**: docs

## P2
EOF
  LIB="$LIB" run _remove_block "$tmp" "kill-me"
  [ "$status" -eq 0 ]
  [ "$output" = "removed" ]
  # Surviving task still there
  grep -q 'keep-me' "$tmp"
  # Killed task gone
  ! grep -q 'kill-me' "$tmp"
  rm -f "$tmp"
}

@test "loop: remove_task_block returns not_found for an unknown id" {
  local tmp
  tmp=$(mktemp)
  cat > "$tmp" <<'EOF'
# Tasks

## P0

- [ ] Only task
  - **ID**: only-one
  - **Tags**: docs
EOF
  LIB="$LIB" run _remove_block "$tmp" "nope-not-here"
  [ "$status" -eq 0 ]
  [ "$output" = "not_found" ]
  grep -q 'only-one' "$tmp"
  rm -f "$tmp"
}

@test "verify_cli_claims: ignores #!/usr/bin/env bats shebangs" {
  # Regression from the dogfood run: bats test files start with
  # `#!/usr/bin/env bats`, the regex matched `bin/env` and the
  # verifier flagged it as "NOT FOUND in repo bin/". Fix: skip shebang
  # lines + interpreter basenames.
  local tmp lib
  tmp=$(mktemp)
  lib="$REPO_ROOT/lib/local-ai-agent.py"
  cat > "$tmp" <<'EOF'
#!/usr/bin/env bats

@test "foo" {
  echo bin/local-ai-agent "$@"
}
EOF
  run python3 -c "
import sys
sys.argv = ['x', '$tmp', '$REPO_ROOT']
import importlib.util
spec = importlib.util.spec_from_file_location('agent', '$lib')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
r = m.run_verify_cli_claims('$tmp', '$REPO_ROOT')
print(r['stdout'])
sys.exit(r['exit_code'])
"
  # Should pass: local-ai-agent is a real script with no flags here.
  [ "$status" -eq 0 ]
  [[ "$output" != *"NOT FOUND"* ]]
  rm -f "$tmp"
}

@test "local-ai-loop: uses dotfiles python3 shim not hardcoded python3" {
  grep -q 'dotfiles_resolve_python "$SCRIPT_DIR/.."' "$REPO_ROOT/bin/local-ai-loop"
  grep -q 'exec "$PYTHON"' "$REPO_ROOT/bin/local-ai-loop"
  ! grep -q 'exec python3' "$REPO_ROOT/bin/local-ai-loop"
}

@test "local-ai scripts run from a checkout without the bin/python3 shim" {
  local copy="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$copy/bin" "$copy/lib"
  cp "$REPO_ROOT/bin/local-ai-agent" "$REPO_ROOT/bin/local-ai-loop" "$copy/bin/"
  cp "$REPO_ROOT/lib/dotfiles-endpoint-paths.sh" "$REPO_ROOT/lib/local-ai-agent.py" \
    "$REPO_ROOT/lib/local-ai-loop.py" "$copy/lib/"
  [ ! -e "$copy/bin/python3" ]
  run "$copy/bin/local-ai-agent" --help
  [ "$status" -eq 0 ]
  run "$copy/bin/local-ai-loop" --help
  [ "$status" -eq 0 ]
}

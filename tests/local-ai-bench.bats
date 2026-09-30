#!/usr/bin/env bats
# Pin `bin/local-ai-bench` output-format invariants so a regression in
# the bench's CLI surface or table layout shows up in CI.

load test_helper

# Resolve a concrete interpreter at file-load time, BEFORE test_helper's
# setup() overrides HOME — the dotfiles bin/python3 shim locates uv python
# under $HOME and prints "uv-managed python 3.13 not found" inside the
# isolated test HOME. sys.executable is HOME-independent afterwards.
TEST_PYTHON3="${TEST_PYTHON3:-$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null || command -v python3)}"

@test "bench: --help exits 0 and mentions the --backend flag" {
  run bin/local-ai-bench --help
  [ "$status" -eq 0 ]
  # The --help blurb must advertise both old + new flags.
  [[ "$output" == *"--cold"* ]]
  [[ "$output" == *"--backend"* ]]
}

@test "bench: rejects unknown flags" {
  # bats `run` merges stderr into $output by default; checking $output
  # is sufficient and portable across bats versions that don't expose
  # `--separate-stderr`.
  run bin/local-ai-bench --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown arg"* ]]
}

@test "bench: --backend llamacpp gracefully skips when llama-server is missing" {
  # Putting only /usr/bin in PATH keeps bash available (it's at
  # /bin/bash so the #!/usr/bin/env shebang resolves) but excludes
  # llama-server's likely homes (/usr/local/bin, /opt/homebrew/bin).
  # Also nuke the /usr/local/bin/llama-server fallback the script tries
  # by running in a sub-shell that lacks the binary on disk — for this
  # test we just verify the PATH-only branch.
  run env PATH=/bin:/usr/bin bin/local-ai-bench --backend llamacpp
  # If llama-server happens to exist at /usr/local/bin, the script
  # SHOULD find it; otherwise it MUST exit 1 with the install hint.
  if [ -x "/usr/local/bin/llama-server" ]; then
    skip "llama-server is installed at /usr/local/bin — graceful-skip branch can't be exercised"
  fi
  [ "$status" -eq 1 ]
  [[ "$output" == *"llama-server not installed"* ]]
}

@test "bench: default backend output has 4 numbered rows (against mock Ollama)" {
  # No more conditional skip — point bench at tests/fixtures/mock-ollama.py
  # so this test runs in CI even when Ollama isn't installed.
  # bin/local-ai-bench invokes the dotfiles bin/python3 shim, which is
  # HOME-sensitive (uv python lives under $HOME). Seed the shim's resolved-
  # path cache inside the isolated test HOME — same pattern as
  # tests/chrome-enforce-profile.bats.
  [ -n "$TEST_PYTHON3" ] || skip "no python3 available to seed the shim cache"
  mkdir -p "$HOME/.cache/dotfiles"
  echo "$TEST_PYTHON3" > "$HOME/.cache/dotfiles/uv-python3-path"
  local port=$((19000 + RANDOM % 1000))
  "$TEST_PYTHON3" "$BATS_TEST_DIRNAME/fixtures/mock-ollama.py" "$port" \
    >"$BATS_TMPDIR/mock-ollama.log" 2>&1 &
  local mock_pid=$!
  # Wait up to 2s for the port to be listening.
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if nc -z 127.0.0.1 "$port" 2>/dev/null; then break; fi
    sleep 0.2
  done
  run env OLLAMA_HOST="http://127.0.0.1:$port" bin/local-ai-bench
  command kill "$mock_pid" 2>/dev/null || true
  wait "$mock_pid" 2>/dev/null || true
  if [ "$status" -eq 137 ]; then
    # Observed 2026-06-12 on the managed-endpoint setup: the bench's python
    # heredoc gets SIGKILLed when run UNDER BATS on this host, while the
    # identical invocation passes outside bats (HOME-isolated repro:
    # `HOME=$(mktemp -d) OLLAMA_HOST=… bin/local-ai-bench` → rc=0).
    # Endpoint-security behavioral kill; forensics tracked in TASKS.md
    # (local-ai-bench-sigkill-under-bats). Skip rather than mask: hosts
    # where the bench survives still assert the full table shape.
    skip "bench python SIGKILLed under bats on this host (endpoint security) — see TASKS.md local-ai-bench-sigkill-under-bats"
  fi
  [ "$status" -eq 0 ]
  # Each row starts with a 1- or 2-char right-justified index. Match
  # either ` 1 ` or `  1 ` so changes to the column width don't break
  # the test.
  local row_count
  row_count=$(printf '%s\n' "$output" | grep -cE '^[[:space:]]+[1-4][[:space:]]+[0-9]')
  [ "$row_count" -eq 4 ]
}

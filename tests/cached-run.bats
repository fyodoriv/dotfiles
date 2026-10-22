#!/usr/bin/env bats
# Tests for bin/cached-run — content-hash-based command caching.

SCRIPT="$BATS_TEST_DIRNAME/../bin/cached-run"

setup_file() {
  # Create the git repo once — tests reset it via git checkout
  export FILE_REPO="$BATS_FILE_TMPDIR/repo"
  mkdir -p "$FILE_REPO"
  git -C "$FILE_REPO" init --quiet
  git -C "$FILE_REPO" config user.email "test@test.com"
  git -C "$FILE_REPO" config user.name "Test"
  git -C "$FILE_REPO" config core.hooksPath /dev/null
  echo "hello" > "$FILE_REPO/file.txt"
  git -C "$FILE_REPO" add file.txt
  git -C "$FILE_REPO" commit -m "chore: initial" --quiet
}

setup() {
  TEST_DIR="$(mktemp -d)"
  export CACHED_RUN_DIR="$TEST_DIR/cache"
  # Fast copy of the pre-built repo (cp -r is much faster than git init + commit)
  TEST_REPO="$TEST_DIR/repo"
  cp -r "$FILE_REPO" "$TEST_REPO"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Basic functionality ──────────────────────────────────────────────

@test "cached-run with no args shows usage and exits 1" {
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "cached-run --help exits 0 and shows usage" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"Examples:"* ]]
}

@test "cached-run -h exits 0 and shows usage" {
  run "$SCRIPT" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

# ── Cache hit / miss ─────────────────────────────────────────────────

@test "first run executes the command" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "executed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"executed"* ]]
}

@test "second run returns cached result" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "first"
  [ "$status" -eq 0 ]

  run "$SCRIPT" echo "first"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
  # The actual "first" should NOT appear (command was not re-run)
  [[ "$output" != *$'\n'"first" ]]
}

@test "cache creates a .result file" {
  cd "$TEST_REPO"
  run "$SCRIPT" true
  [ "$status" -eq 0 ]

  local result_count
  result_count=$(find "$CACHED_RUN_DIR" -name "*.result" | wc -l | tr -d ' ')
  [ "$result_count" -eq 1 ]
}

@test "cache file contains command and timestamp" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo hello
  [ "$status" -eq 0 ]

  local result_file
  result_file=$(find "$CACHED_RUN_DIR" -name "*.result" -type f | head -1)
  [ -f "$result_file" ]

  # First line is the command
  local cached_cmd
  cached_cmd=$(head -1 "$result_file")
  [ "$cached_cmd" = "echo hello" ]

  # Second line is a date
  local cached_date
  cached_date=$(sed -n '2p' "$result_file")
  [[ "$cached_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]
}

# ── Cache invalidation ──────────────────────────────────────────────

@test "modifying a tracked file invalidates cache" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "run1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"run1"* ]]

  # Modify a tracked file
  echo "changed" >> "$TEST_REPO/file.txt"

  run "$SCRIPT" echo "run2"
  [ "$status" -eq 0 ]
  # Should re-execute, not return cached
  [[ "$output" == *"run2"* ]]
  [[ "$output" != *"cached"* ]]
}

@test "staging a change invalidates cache" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "before-stage"
  [ "$status" -eq 0 ]

  echo "staged" >> "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" add file.txt

  run "$SCRIPT" echo "after-stage"
  [ "$status" -eq 0 ]
  [[ "$output" == *"after-stage"* ]]
  [[ "$output" != *"cached"* ]]
}

@test "committing a change invalidates cache" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "before-commit"
  [ "$status" -eq 0 ]

  echo "new" > "$TEST_REPO/new.txt"
  git -C "$TEST_REPO" add new.txt
  git -C "$TEST_REPO" commit -m "chore: add new" --quiet

  run "$SCRIPT" echo "after-commit"
  [ "$status" -eq 0 ]
  [[ "$output" == *"after-commit"* ]]
  [[ "$output" != *"cached"* ]]
}

@test "adding an untracked file invalidates cache" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "before-untracked"
  [ "$status" -eq 0 ]

  # Create a new untracked file (not in .gitignore)
  echo "new" > "$TEST_REPO/untracked.txt"

  run "$SCRIPT" echo "after-untracked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"after-untracked"* ]]
  [[ "$output" != *"cached"* ]]
}

@test "editing an untracked file's content invalidates cache (same command)" {
  cd "$TEST_REPO"
  echo "one" > "$TEST_REPO/untracked.txt"
  run "$SCRIPT" echo "untracked-content"
  [ "$status" -eq 0 ]
  run "$SCRIPT" echo "untracked-content"
  [[ "$output" == *"cached"* ]]

  # Same name, new content: a step that reads this file must re-run.
  echo "two" > "$TEST_REPO/untracked.txt"
  run "$SCRIPT" echo "untracked-content"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cached"* ]]
}

@test "editing a tracked file invalidates cache (same command)" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "tracked-content"
  run "$SCRIPT" echo "tracked-content"
  [[ "$output" == *"cached"* ]]
  echo "changed" >> "$TEST_REPO/file.txt"
  run "$SCRIPT" echo "tracked-content"
  [[ "$output" != *"cached"* ]]
}

@test "reverting a change restores cache hit" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "original"
  [ "$status" -eq 0 ]

  # Modify and then revert
  echo "changed" >> "$TEST_REPO/file.txt"
  git -C "$TEST_REPO" checkout -- file.txt

  run "$SCRIPT" echo "should-be-cached"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

@test "gitignored files do not invalidate cache" {
  cd "$TEST_REPO"
  echo "node_modules/" > "$TEST_REPO/.gitignore"
  git -C "$TEST_REPO" add .gitignore
  git -C "$TEST_REPO" commit -m "chore: add gitignore" --quiet

  # Cache AFTER the gitignore commit (same command both times)
  run "$SCRIPT" echo "check-ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-ignored"* ]]
  [[ "$output" != *"cached"* ]]

  # Create a gitignored file — should NOT invalidate
  mkdir -p "$TEST_REPO/node_modules"
  echo "stuff" > "$TEST_REPO/node_modules/pkg.js"

  run "$SCRIPT" echo "check-ignored"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

# ── Different commands ───────────────────────────────────────────────

@test "different commands have separate cache entries" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "cmd-a"
  [ "$status" -eq 0 ]

  # Different command should not be cached
  run "$SCRIPT" echo "cmd-b"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cmd-b"* ]]
  [[ "$output" != *"cached"* ]]

  # Original command should still be cached
  run "$SCRIPT" echo "cmd-a"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

# ── Failed commands ──────────────────────────────────────────────────

@test "failed commands are not cached" {
  cd "$TEST_REPO"
  run "$SCRIPT" false
  [ "$status" -eq 1 ]

  # Should re-run, not return cached
  run "$SCRIPT" false
  [ "$status" -eq 1 ]

  # No cache files should exist
  local result_count
  result_count=$(find "$CACHED_RUN_DIR" -name "*.result" 2>/dev/null | wc -l | tr -d ' ')
  [ "$result_count" -eq 0 ]
}

@test "failed command preserves exit code" {
  cd "$TEST_REPO"
  run "$SCRIPT" bash -c "exit 42"
  [ "$status" -eq 42 ]
}

# ── Not in a git repo ────────────────────────────────────────────────

@test "running outside git repo fails with error" {
  cd "$TEST_DIR"
  run "$SCRIPT" echo "no-repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repository"* ]]
}

# ── --clear ──────────────────────────────────────────────────────────

@test "--clear removes cache for current repo" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "to-clear"
  [ "$status" -eq 0 ]

  # Verify cache exists
  local result_count
  result_count=$(find "$CACHED_RUN_DIR" -name "*.result" | wc -l | tr -d ' ')
  [ "$result_count" -eq 1 ]

  run "$SCRIPT" --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]

  # Verify cache is gone
  result_count=$(find "$CACHED_RUN_DIR" -name "*.result" 2>/dev/null | wc -l | tr -d ' ')
  [ "$result_count" -eq 0 ]
}

@test "--clear outside git repo fails" {
  cd "$TEST_DIR"
  run "$SCRIPT" --clear
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repository"* ]]
}

@test "--clear with no existing cache prints message" {
  cd "$TEST_REPO"
  run "$SCRIPT" --clear
  [ "$status" -eq 0 ]
  [[ "$output" == *"No cache"* ]]
}

# ── --clear-all ──────────────────────────────────────────────────────

@test "--clear-all removes entire cache directory" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "cached"
  [ "$status" -eq 0 ]
  [ -d "$CACHED_RUN_DIR" ]

  run "$SCRIPT" --clear-all
  [ "$status" -eq 0 ]
  [[ "$output" == *"cleared"* ]]
  [ ! -d "$CACHED_RUN_DIR" ]
}

# ── --status ─────────────────────────────────────────────────────────

@test "--status shows cached commands" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "status-test"
  [ "$status" -eq 0 ]

  run "$SCRIPT" --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Entries: 1"* ]]
  [[ "$output" == *"echo status-test"* ]]
}

@test "--status with no cache prints message" {
  cd "$TEST_REPO"
  run "$SCRIPT" --status
  [ "$status" -eq 0 ]
  [[ "$output" == *"No cached results"* ]]
}

@test "--status outside git repo fails" {
  cd "$TEST_DIR"
  run "$SCRIPT" --status
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in a git repository"* ]]
}

# ── Multiple repos ───────────────────────────────────────────────────

@test "different repos have independent caches" {
  # Create second repo
  local repo2="$TEST_DIR/repo2"
  mkdir -p "$repo2"
  git -C "$repo2" init --quiet
  git -C "$repo2" config user.email "test@test.com"
  git -C "$repo2" config user.name "Test"
  git -C "$repo2" config core.hooksPath /dev/null
  echo "world" > "$repo2/file.txt"
  git -C "$repo2" add file.txt
  git -C "$repo2" commit -m "chore: initial" --quiet

  # Cache in repo1
  cd "$TEST_REPO"
  run "$SCRIPT" echo "repo1"
  [ "$status" -eq 0 ]

  # Should not be cached in repo2
  cd "$repo2"
  run "$SCRIPT" echo "repo1"
  [ "$status" -eq 0 ]
  [[ "$output" != *"cached"* ]]
}

# ── Subdirectory ─────────────────────────────────────────────────────

@test "cache works from a subdirectory of the repo" {
  mkdir -p "$TEST_REPO/sub/dir"
  cd "$TEST_REPO"
  run "$SCRIPT" echo "from-root"
  [ "$status" -eq 0 ]

  # Same command from subdirectory should hit cache
  cd "$TEST_REPO/sub/dir"
  run "$SCRIPT" echo "from-root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

# ── Script hygiene ───────────────────────────────────────────────────

@test "script is executable" {
  [ -x "$SCRIPT" ]
}

@test "script has correct shebang" {
  local shebang
  shebang=$(head -1 "$SCRIPT")
  [ "$shebang" = "#!/bin/bash" ]
}

@test "script uses strict mode" {
  grep -q "set -euo pipefail" "$SCRIPT"
}

# ── Edge cases ───────────────────────────────────────────────────────

@test "command with special characters in args works" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]

  run "$SCRIPT" echo "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

@test "CACHED_RUN_DIR can be overridden" {
  cd "$TEST_REPO"
  local custom_dir="$TEST_DIR/custom-cache"
  CACHED_RUN_DIR="$custom_dir" run "$SCRIPT" echo "custom"
  [ "$status" -eq 0 ]
  [ -d "$custom_dir" ]
}

@test "cache survives after clearing and re-running" {
  cd "$TEST_REPO"
  run "$SCRIPT" echo "round1"
  [ "$status" -eq 0 ]

  run "$SCRIPT" --clear
  [ "$status" -eq 0 ]

  # Should re-execute after clear
  run "$SCRIPT" echo "round2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"round2"* ]]
  [[ "$output" != *"cached"* ]]

  # Now should be cached again
  run "$SCRIPT" echo "round2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

# ── Per-file mode (make lint) ────────────────────────────────────────

# A fake checker: logs each file it gets and fails on a file that says BAD.
per_file_setup() {
  CHECK="$TEST_DIR/check"
  CALLS="$TEST_DIR/calls.log"
  printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "%s"\nif grep -q BAD "$1"; then echo "BAD in $1"; exit 3; fi\n' "$CALLS" > "$CHECK"
  chmod +x "$CHECK"
  mkdir -p "$TEST_REPO/bin" "$TEST_REPO/lib"
  printf 'echo a\n' > "$TEST_REPO/bin/a"
  printf 'echo b\n' > "$TEST_REPO/bin/b"
  cd "$TEST_REPO"
}

# Print the files the checker got since the last call (sorted), then reset.
calls() {
  [ -f "$CALLS" ] && LC_ALL=C sort "$CALLS" | tr '\n' ' '
  : > "$CALLS"
}

@test "--per-file checks each file once, then reuses each pass" {
  per_file_setup
  run "$SCRIPT" --per-file --jobs 2 "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a bin/b " ]
  [[ "$output" == *"2 checked"* ]]

  run "$SCRIPT" --per-file --jobs 2 "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ -z "$(calls)" ]
  [[ "$output" == *"2 unchanged"* ]]
}

@test "--per-file re-checks only the edited file" {
  per_file_setup
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  calls >/dev/null
  echo "echo a2" >> bin/a
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a " ]
}

@test "--per-file shows a failing file's output, fails, and keeps the other passes" {
  per_file_setup
  echo "BAD" >> bin/b
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 3 ]
  [[ "$output" == *"BAD in bin/b"* ]]
  [[ "$output" == *"1 failed"* ]]
  calls >/dev/null

  # The failure is not cached; the pass is.
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 3 ]
  [ "$(calls)" = "bin/b " ]
}

@test "--per-file re-checks a file when a file it sources changes" {
  per_file_setup
  printf '# shellcheck source=lib/x.sh\nsource "$DIR/lib/x.sh"\n' > bin/a
  printf 'X=1\n' > lib/x.sh
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  calls >/dev/null
  printf 'X=2\n' > lib/x.sh
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a " ]
}

@test "--per-file follows sources two levels deep and from the file's folder" {
  per_file_setup
  # bin/a names its lib relative to its own folder; the lib sources a
  # second lib with a constant path.
  printf '# shellcheck source=../lib/x.sh\n. "$DIR/../lib/x.sh"\n' > bin/a
  printf 'source lib/y.sh\n' > lib/x.sh
  printf 'Y=1\n' > lib/y.sh
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  calls >/dev/null
  printf 'Y=2\n' > lib/y.sh
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a " ]
}

@test "--per-file shares passes across worktrees and clones of the repo" {
  per_file_setup
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  calls >/dev/null
  cp -R "$TEST_REPO" "$TEST_DIR/clone"
  cd "$TEST_DIR/clone"
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ -z "$(calls)" ]
}

@test "--per-file re-checks every file when --key changes" {
  per_file_setup
  run "$SCRIPT" --per-file --key "tool 1.0" "$CHECK" -- bin/a bin/b
  calls >/dev/null
  run "$SCRIPT" --per-file --key "tool 1.0" "$CHECK" -- bin/a bin/b
  [ -z "$(calls)" ]
  run "$SCRIPT" --per-file --key "tool 2.0" "$CHECK" -- bin/a bin/b
  [ "$(calls)" = "bin/a bin/b " ]
}

@test "--per-file never caches a file with a source-path directive" {
  per_file_setup
  printf '# shellcheck source-path=lib\necho a\n' > bin/a
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  calls >/dev/null
  run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a " ]
}

@test "--per-file still checks and passes when the cache folder cannot be written" {
  per_file_setup
  # A plain file where the cache folder should be: mkdir fails, as in the
  # agent sandbox.
  : > "$TEST_DIR/not-a-dir"
  CACHED_RUN_DIR="$TEST_DIR/not-a-dir/cache" run "$SCRIPT" --per-file "$CHECK" -- bin/a bin/b
  [ "$status" -eq 0 ]
  [ "$(calls)" = "bin/a bin/b " ]
}

@test "--per-file without -- before the files fails with usage" {
  per_file_setup
  run "$SCRIPT" --per-file "$CHECK" bin/a
  [ "$status" -eq 2 ]
  [[ "$output" == *"--"* ]]
}

@test "--per-file re-runs real shellcheck when a sourced lib drops a variable" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  per_file_setup
  printf 'external-sources=true\n' > .shellcheckrc
  # (SC2154 skips ALL_CAPS names, so the variable is lowercase.)
  printf '#!/bin/bash\n# shellcheck source=lib/x.sh\nsource "$DIR/lib/x.sh"\necho "$my_var"\n' > bin/a
  printf '#!/bin/bash\n# shellcheck disable=SC2034\nmy_var=1\n' > lib/x.sh
  run "$SCRIPT" --per-file shellcheck -S warning -- bin/a
  [ "$status" -eq 0 ]
  # Without my_var in the lib, bin/a references an unassigned variable.
  printf '#!/bin/bash\nother=1\nexport other\n' > lib/x.sh
  run "$SCRIPT" --per-file shellcheck -S warning -- bin/a
  [ "$status" -ne 0 ]
  [[ "$output" == *"SC2154"* ]]
}

@test "make lint uses the per-file cache and make lint-full skips it" {
  local mk="$BATS_TEST_DIRNAME/../Makefile"
  grep -qE 'cached-run --per-file .*shellcheck \$\(LINT_FLAGS\) -- \$\(SCRIPTS\)' "$mk"
  grep -qE '^lint-full:' "$mk"
  grep -qE '^	@\$\(FULLPOWER\) shellcheck \$\(LINT_FLAGS\) \$\(SCRIPTS\)' "$mk"
  # The cache key covers the shellcheck version and the repo .shellcheckrc.
  grep -qE 'shellcheck --version' "$mk"
  grep -qE 'hash-object \.shellcheckrc' "$mk"
}

@test "repo .shellcheckrc sets no source-path that the per-file cache cannot follow" {
  # bin/cached-run --per-file looks up a sourced path from the repo root and
  # from the script's folder (SCRIPTDIR). Another source-path folder would
  # hide a dependency from the cache key: teach cached-run first.
  run grep -E '^[[:space:]]*source-path=' "$BATS_TEST_DIRNAME/../.shellcheckrc"
  local bad
  bad="$(printf '%s\n' "$output" | grep -vE '^[[:space:]]*source-path=SCRIPTDIR[[:space:]]*$' || true)"
  [ -z "$bad" ] || { echo "$bad"; return 1; }
}

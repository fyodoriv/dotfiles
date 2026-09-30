#!/usr/bin/env bats
# Tests for dotfiles-doctor check/fix/override logic

load test_helper

# ── Test speed optimization ─────────────────────────────────────────
# The default doctor run takes ~30s (over 200 checks across all modules).
# CLI-shape tests (--quiet, --json, --report, --fix-all, --watch) only need
# *some* doctor output to verify structure — they don't need every module.
# Pass `--module cursor` to scope each invocation to the smallest module
# (~3s, 2 checks). Cuts this file's runtime ~10x.
#
# In addition, most CLI-shape tests check different substrings of the
# *same* invocation (e.g. the 5 "normal mode prints X count" tests).
# Instead of re-invoking doctor for each, setup_file() runs each mode
# once and caches the output; tests read the cache via load_cached_*.
#
# The genuine perf-regression test ("doctor --quiet completes in under 60s")
# intentionally runs the full doctor and is exempt from both optimizations.
DOCTOR_TINY_MODULE="cursor"

setup_file() {
  export DOCTOR_CACHE_DIR="$(mktemp -d)"
  export DOCTOR_CACHE_HOME="$HOME"
  export DOCTOR_CACHE_DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  # Unique lock file per file-level setup so doctor.bats's setup_file
  # doesn't compete with other parallel test files (smoke.bats also
  # invokes the doctor, and the default $HOME/.dotfiles.lock is shared).
  export DOTFILES_LOCK="$DOCTOR_CACHE_DIR/dotfiles.lock"
  local bin="$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"

  # Cache one doctor run per CLI mode. Capture the exit status WITHOUT
  # letting a non-zero exit abort setup_file (bats runs it under set -eET):
  # dotfiles-doctor exits non-zero whenever the machine has ANY failing check
  # (e.g. an un-symlinked editor setting) — unrelated to these CLI-shape
  # assertions. `|| status=$?` is the set -e-safe capture; the `.status` files
  # still record the real exit code for the tests that read them.
  _doctor_cache_run() { # $1 = cache name; rest = extra flags
    local name="$1"
    shift
    local status=0
    bash "$bin" --module "$DOCTOR_TINY_MODULE" "$@" \
      > "$DOCTOR_CACHE_DIR/$name.out" 2>&1 || status=$?
    echo "$status" > "$DOCTOR_CACHE_DIR/$name.status"
  }

  _doctor_cache_run normal
  _doctor_cache_run quiet --quiet
  _doctor_cache_run report --report
  _doctor_cache_run json --json
  _doctor_cache_run fixall --fix-all
}

teardown_file() {
  rm -rf "$DOCTOR_CACHE_DIR"
}

load_cached() {
  # Usage: load_cached <mode>, where <mode> is normal|quiet|report|json|fixall
  output="$(cat "$DOCTOR_CACHE_DIR/$1.out")"
  status="$(cat "$DOCTOR_CACHE_DIR/$1.status")"
}

# We test the doctor's core functions by sourcing just the function definitions
setup() {
  # Call parent setup for temp dirs
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Doctor-specific state
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  # Doctor helpers (same as in dotfiles-doctor)
  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    local desc="$dst → dotfiles"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$desc"
    elif $FIX_MODE; then
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      mkdir -p "$(dirname "$dst")"
      ln -s "$src" "$dst"
      fixed "$desc"
    else
      fail "$desc"
    fi
  }

  check_managed() {
    local id="$1" src="$2" dst="$3"
    local desc="$dst → dotfiles"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$desc (symlink)"
    elif [ -f "$dst" ] && [ -f "$src" ] && diff -q "$dst" "$src" >/dev/null 2>&1; then
      pass "$desc (managed)"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      fixed "$desc"
    else
      fail "$desc"
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "check passes when test command succeeds" {
  check "test.pass" "should pass" "true" ""
  [ "$pass_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "check fails when test command fails" {
  check "test.fail" "should fail" "false" ""
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 1 ]
}

@test "check auto-fixes when FIX_MODE is true and fix_cmd provided" {
  FIX_MODE=true
  touch "$TEST_DIR/marker"
  check "test.fixable" "should fix" "false" "rm $TEST_DIR/marker"
  [ "$fix_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
  [ ! -f "$TEST_DIR/marker" ]
}

@test "check skips when check ID is in overrides file" {
  echo "test.skipped" >> "$OVERRIDES_FILE"
  check "test.skipped" "should skip" "false" ""
  [ "$skip_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "check does not fix when FIX_MODE is false even with fix_cmd" {
  FIX_MODE=false
  touch "$TEST_DIR/marker"
  check "test.noop" "should fail not fix" "false" "rm $TEST_DIR/marker"
  [ "$fail_count" -eq 1 ]
  [ "$fix_count" -eq 0 ]
  [ -f "$TEST_DIR/marker" ]
}

@test "check_symlink passes for correct symlink" {
  create_file "$TEST_DOTFILES/home/gitconfig" "[core]"
  mkdir -p "$TEST_HOME"
  ln -s "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"

  check_symlink "symlink.git" "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"
  [ "$pass_count" -eq 1 ]
}

@test "check_symlink fails for missing symlink" {
  create_file "$TEST_DOTFILES/home/gitconfig" "[core]"

  check_symlink "symlink.git" "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"
  [ "$fail_count" -eq 1 ]
}

@test "check_symlink auto-fixes missing symlink in FIX_MODE" {
  create_file "$TEST_DOTFILES/home/gitconfig" "[core]"
  FIX_MODE=true

  check_symlink "symlink.git" "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"
  [ "$fix_count" -eq 1 ]
  [ -L "$TEST_HOME/.gitconfig" ]
  [ "$(readlink "$TEST_HOME/.gitconfig")" = "$TEST_DOTFILES/home/gitconfig" ]
}

@test "check_symlink auto-fixes wrong symlink target in FIX_MODE" {
  create_file "$TEST_DOTFILES/home/gitconfig" "[core] new"
  create_file "$TEST_DIR/old/gitconfig" "[core] old"
  mkdir -p "$TEST_HOME"
  ln -s "$TEST_DIR/old/gitconfig" "$TEST_HOME/.gitconfig"
  FIX_MODE=true

  check_symlink "symlink.git" "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"
  [ "$fix_count" -eq 1 ]
  [ "$(readlink "$TEST_HOME/.gitconfig")" = "$TEST_DOTFILES/home/gitconfig" ]
}

@test "check_symlink skips overridden checks" {
  echo "symlink.git" >> "$OVERRIDES_FILE"
  check_symlink "symlink.git" "$TEST_DOTFILES/home/gitconfig" "$TEST_HOME/.gitconfig"
  [ "$skip_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "multiple checks accumulate counters correctly" {
  check "a" "pass" "true" ""
  check "b" "fail" "false" ""
  check "c" "pass" "true" ""
  echo "d" >> "$OVERRIDES_FILE"
  check "d" "skip" "false" ""

  [ "$pass_count" -eq 2 ]
  [ "$fail_count" -eq 1 ]
  [ "$skip_count" -eq 1 ]
}

@test "check_managed passes for matching copy-mode file" {
  create_file "$TEST_DOTFILES/dot_editorconfig" "root = true"
  create_file "$TEST_HOME/.editorconfig" "root = true"

  check_managed "managed.ec" "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  [ "$pass_count" -eq 1 ]
}

@test "check_managed fails for mismatched copy-mode file" {
  create_file "$TEST_DOTFILES/dot_editorconfig" "root = true"
  create_file "$TEST_HOME/.editorconfig" "root = false"

  check_managed "managed.ec" "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  [ "$fail_count" -eq 1 ]
}

@test "check_managed fails for missing destination file" {
  create_file "$TEST_DOTFILES/dot_editorconfig" "root = true"

  check_managed "managed.ec" "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  [ "$fail_count" -eq 1 ]
}

@test "check_managed auto-fixes by copying in FIX_MODE" {
  create_file "$TEST_DOTFILES/dot_editorconfig" "root = true"
  FIX_MODE=true

  check_managed "managed.ec" "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  [ "$fix_count" -eq 1 ]
  [ -f "$TEST_HOME/.editorconfig" ]
  [ "$(cat "$TEST_HOME/.editorconfig")" = "root = true" ]
}

@test "check_managed passes for symlink pointing to source" {
  create_file "$TEST_DOTFILES/home/zshrc" "# zshrc"
  ln -s "$TEST_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"

  check_managed "managed.zshrc" "$TEST_DOTFILES/home/zshrc" "$TEST_HOME/.zshrc"
  [ "$pass_count" -eq 1 ]
}

@test "check_managed skips overridden checks" {
  echo "managed.ec" >> "$OVERRIDES_FILE"
  check_managed "managed.ec" "$TEST_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  [ "$skip_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

# ── check_defaults tests ────────────────────────────────────────────

# check_defaults uses macOS `defaults` command which reads/writes plist domains.
# We mock it by creating a temp plist and overriding the domain to point there.

setup_defaults_mock() {
  # Create a mock defaults command that reads/writes to a temp file
  MOCK_DEFAULTS_STORE="$TEST_DIR/defaults_store"
  mkdir -p "$MOCK_DEFAULTS_STORE"

  # Override check_defaults to use our mock
  check_defaults() {
    local id="$1" desc="$2" domain="$3" key="$4" expected="$5" type="$6"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi

    local store_file="$MOCK_DEFAULTS_STORE/${domain}.${key}"
    local current=""
    [ -f "$store_file" ] && current=$(cat "$store_file")

    if [ "$current" = "$expected" ]; then
      pass "$desc"
    elif $FIX_MODE; then
      echo "$expected" > "$store_file"
      fixed "$desc"
    else
      fail "$desc (is: $current, want: $expected)"
    fi
  }
}

@test "check_defaults passes when value matches expected" {
  setup_defaults_mock
  echo "1" > "$MOCK_DEFAULTS_STORE/com.apple.finder.ShowPathbar"

  check_defaults "defaults.pathbar" "Finder path bar" "com.apple.finder" "ShowPathbar" "1" "bool"
  [ "$pass_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

@test "check_defaults fails when value does not match" {
  setup_defaults_mock
  echo "0" > "$MOCK_DEFAULTS_STORE/com.apple.finder.ShowPathbar"

  check_defaults "defaults.pathbar" "Finder path bar" "com.apple.finder" "ShowPathbar" "1" "bool"
  [ "$fail_count" -eq 1 ]
  [ "$pass_count" -eq 0 ]
}

@test "check_defaults fails when key is missing" {
  setup_defaults_mock

  check_defaults "defaults.pathbar" "Finder path bar" "com.apple.finder" "ShowPathbar" "1" "bool"
  [ "$fail_count" -eq 1 ]
}

@test "check_defaults auto-fixes in FIX_MODE" {
  setup_defaults_mock
  FIX_MODE=true
  echo "0" > "$MOCK_DEFAULTS_STORE/com.apple.finder.ShowPathbar"

  check_defaults "defaults.pathbar" "Finder path bar" "com.apple.finder" "ShowPathbar" "1" "bool"
  [ "$fix_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
  [ "$(cat "$MOCK_DEFAULTS_STORE/com.apple.finder.ShowPathbar")" = "1" ]
}

@test "check_defaults skips overridden checks" {
  setup_defaults_mock
  echo "defaults.pathbar" >> "$OVERRIDES_FILE"

  check_defaults "defaults.pathbar" "Finder path bar" "com.apple.finder" "ShowPathbar" "1" "bool"
  [ "$skip_count" -eq 1 ]
  [ "$fail_count" -eq 0 ]
}

# ── --quiet mode tests ─────────────────────────────────────────────

@test "doctor --quiet outputs exactly one line" {
  load_cached quiet
  line_count=$(echo "$output" | wc -l)
  [ "$line_count" -eq 1 ]
}

@test "doctor --quiet does not print section headers" {
  load_cached quiet
  [[ "$output" != *"═══"* ]]
  [[ "$output" != *"───"* ]]
}

@test "doctor --quiet includes pass count" {
  load_cached quiet
  [[ "$output" == *"✓"* ]]
}

# ── Summary output tests ────────────────────────────────────────────

@test "doctor normal mode prints total count in summary" {
  load_cached normal
  [[ "$output" == *"total"* ]]
}

@test "doctor normal mode prints passed count in summary" {
  load_cached normal
  [[ "$output" == *"passed"* ]]
}

@test "doctor normal mode prints failed count in summary" {
  load_cached normal
  [[ "$output" == *"failed"* ]]
}

@test "doctor normal mode prints fixed count in summary" {
  load_cached normal
  [[ "$output" == *"fixed"* ]]
}

@test "doctor normal mode prints skipped count in summary" {
  load_cached normal
  [[ "$output" == *"skipped"* ]]
}

@test "doctor --report includes total in summary table" {
  load_cached report
  [[ "$output" == *"**Total**"* ]]
}

@test "doctor --report includes warned row in summary table" {
  load_cached report
  [[ "$output" == *"Warned"* ]]
}

# ── --fix-all mode tests ────────────────────────────────────────────

@test "doctor --fix-all is accepted as a valid flag" {
  load_cached fixall
  # Should not fail with "unknown option" — exit 0 or 1 (failures) are both valid
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "doctor --fix-all prints summary like --fix" {
  load_cached fixall
  [[ "$output" == *"passed"* ]]
  [[ "$output" == *"fixed"* ]]
}

@test "doctor --fix-all behaves identically to --fix" {
  # This test compares two distinct invocations, so it can't use the
  # cached --fix-all output — we need a fresh --fix run too.
  run env HOME="$DOCTOR_CACHE_HOME" DOTFILES_DIR="$DOCTOR_CACHE_DOTFILES_DIR" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module "$DOCTOR_TINY_MODULE" --fix
  fix_status="$status"

  load_cached fixall
  fixall_status="$status"

  # Same exit code
  [ "$fix_status" -eq "$fixall_status" ]
}

# ── --json mode tests ───────────────────────────────────────────────

@test "doctor --json outputs valid JSON array" {
  load_cached json
  # Should start with [ and end with ]
  [[ "$output" == "["* ]]
  [[ "$output" == *"]" ]]
}

@test "doctor --json results contain id field" {
  load_cached json
  [[ "$output" == *'"id":'* ]]
}

@test "doctor --json results contain status field" {
  load_cached json
  [[ "$output" == *'"status":'* ]]
}

@test "doctor --json results contain module field" {
  load_cached json
  [[ "$output" == *'"module":'* ]]
}

@test "doctor --json results contain message field" {
  load_cached json
  [[ "$output" == *'"message":'* ]]
}

@test "doctor --json does not print section headers" {
  load_cached json
  [[ "$output" != *"═══"* ]]
  [[ "$output" != *"───"* ]]
}

@test "doctor --json piped to jq selects failures" {
  if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
  # Pipe the cached JSON output through jq.
  run bash -c "cat '$DOCTOR_CACHE_DIR/json.out' | jq '.[] | select(.status == \"fail\")'"
  # Should not error — exit 0 means jq parsed it successfully
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "doctor --json includes remediation for advisory warnings" {
  if ! command -v jq &>/dev/null; then skip "jq not installed"; fi
  mkdir -p "$TEST_HOME/.ssh"
  chmod 700 "$TEST_HOME/.ssh"
  echo "machine github.com" > "$TEST_HOME/.netrc"
  chmod 644 "$TEST_HOME/.netrc"
  touch "$TEST_DIR/gitconfig"

  run env \
    HOME="$TEST_HOME" \
    GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig" \
    DOTFILES_LOCK="$TEST_DIR/doctor-json.lock" \
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module security --json

  [[ "$status" -eq 0 || "$status" -eq 1 ]]
  echo "$output" | jq -e '.[] | select(.id == "security.sensitive_perms..netrc" and .status == "warn" and .fix == "chmod 600 ~/.netrc")' >/dev/null
}

@test "doctor --module security does not run agentbrew aggregate health" {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/agentbrew" <<'EOF'
#!/bin/bash
case "$1 $2" in
  "status --ci") echo "agentbrew status --ci should not be called" >&2; exit 42 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  run env \
    HOME="$TEST_HOME" \
    DOTFILES_LOCK="$TEST_DIR/doctor-security.lock" \
    DOTFILES_REPOS_DIR="$TEST_DIR/repos" \
    PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module security --json

  [[ "$output" != *"agentbrew status --ci should not be called"* ]]
  [[ "$output" != *"agentbrew.status"* ]]
}

@test "agentbrew aggregate health uses status ci instead of removed doctor command" {
  mkdir -p "$TEST_DIR/bin"
  mkdir -p "$TEST_HOME/.config/agentbrew"
  echo "state: ok" > "$TEST_HOME/.config/agentbrew/state.yaml"
  echo "mcp: []" > "$TEST_HOME/.config/agentbrew/Agentfile.yaml"
  cat > "$TEST_DIR/bin/agentbrew" << 'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$AGENTBREW_CALL_LOG"
case "$1 $2" in
  "agentfile merge")
    output=""
    previous=""
    for arg in "$@"; do
      if [ "$previous" = "--output" ]; then
        output="$arg"
        break
      fi
      previous="$arg"
    done
    echo "mcp: []" > "$output"
    ;;
  "status --ci") exit 0 ;;
  "doctor ") echo "agentbrew doctor should not be called" >&2; exit 42 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/agentbrew"

  cat > "$TEST_DIR/bin/chezmoi" << 'EOF'
#!/bin/bash
case "$1" in
  doctor) echo "ok version mock" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TEST_DIR/bin/chezmoi"

  run env \
    HOME="$TEST_HOME" \
    BASH_ENV= \
    ENV= \
    AGENTBREW_CALL_LOG="$TEST_DIR/agentbrew-calls.log" \
    DOTFILES_LOCK="$TEST_DIR/doctor-agentbrew.lock" \
    DOTFILES_REPOS_DIR="$TEST_DIR/repos" \
    PATH="$TEST_DIR/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module agentbrew --quiet

  grep -qx 'status --ci' "$TEST_DIR/agentbrew-calls.log"
  ! grep -q '^doctor' "$TEST_DIR/agentbrew-calls.log"
}

# ── Performance regression tests ────────────────────────────────────

@test "doctor --quiet completes in under 90 seconds" {
  # This asserts the normal steady state: warm the successful-only Homebrew
  # bottle signature cache first, then time the full run. Cold audits remain
  # complete security checks, but only run after a bottle inventory change,
  # cache expiry, an explicit refresh, or signing repair.
  # NOTE: this is the only test in this file that runs the FULL doctor —
  # everything else uses --module $DOCTOR_TINY_MODULE for ~10x speedup.
  local performance_lock="$TEST_DIR/doctor-performance.lock"
  run env DOTFILES_LOCK="$performance_lock" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module security --quiet

  SECONDS=0
  run env DOTFILES_LOCK="$performance_lock" \
    bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --quiet
  elapsed=$SECONDS
  [ "$elapsed" -lt 90 ]
}

# ── --watch mode tests ──────────────────────────────────────────────

@test "doctor --watch is accepted as a valid flag" {
  # WATCH_MAX_ITERATIONS=1 exits after 1 iteration — deterministic, no alarm/timeout tricks.
  WATCH_MAX_ITERATIONS=1 WATCH_INTERVAL=1 run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module "$DOCTOR_TINY_MODULE" --watch
  # Should produce output (not "unknown option" or empty)
  [[ "$output" == *"watching"* ]] || [[ "$output" == *"doctor"* ]] || [[ "$output" == *"passed"* ]]
}

@test "doctor --watch shows timestamp in header" {
  WATCH_MAX_ITERATIONS=1 WATCH_INTERVAL=1 run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --module "$DOCTOR_TINY_MODULE" --watch
  # Header includes a time like HH:MM:SS
  [[ "$output" =~ [0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}

@test "doctor --watch shows in help text" {
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --help
  [[ "$output" == *"--watch"* ]]
}

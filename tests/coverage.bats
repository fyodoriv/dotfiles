#!/usr/bin/env bats
# Regression tests for shell coverage verification.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
MAKEFILE="$DOTFILES_DIR/Makefile"
CI_WORKFLOW="$DOTFILES_DIR/.github/workflows/ci.yml"
COVERAGE_CHECK="$DOTFILES_DIR/.github/scripts/check-shell-coverage.sh"
COVERAGE_FLOOR="$DOTFILES_DIR/.shell-coverage-floor"

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

coverage_make_target() {
  awk '
    /^coverage:/ { in_target = 1 }
    in_target && /^[a-zA-Z_-]+:/ && $0 !~ /^coverage:/ { exit }
    in_target { print }
  ' "$MAKEFILE"
}

coverage_workflow_step() {
  awk '
    /name: Run tests with coverage/ { in_step = 1 }
    in_step && /name: Extract coverage percentage/ { exit }
    in_step { print }
  ' "$CI_WORKFLOW"
}

@test "make coverage delegates to bin/dotfiles-coverage" {
  run coverage_make_target
  [ "$status" -eq 0 ]
  [[ "$output" == *"bin/dotfiles-coverage run tests/"* ]]
  [[ "$output" != *"|| true"* ]]
}

@test "bin/dotfiles-coverage does not invoke kcov" {
  # kcov can appear in explanatory comments, but it must never be invoked or
  # required as a runtime dependency. Strip comment lines first, then assert
  # there's no actual kcov call left in the script.
  run bash -c 'grep -vE "^[[:space:]]*#" "$1" | grep -E "(\\bkcov\\b|command -v kcov|brew install.*kcov)"' _ "$DOTFILES_DIR/bin/dotfiles-coverage"
  [ "$status" -ne 0 ]
}

@test "lib/coverage-trap.sh installs xtrace via BASH_ENV" {
  trap_helper="$DOTFILES_DIR/lib/coverage-trap.sh"
  [ -f "$trap_helper" ]
  grep -q 'BASH_XTRACEFD' "$trap_helper"
  grep -q "PS4='COV@" "$trap_helper"
  grep -q 'set -x' "$trap_helper"
}

@test "coverage harness produces a non-empty report on a single test file" {
  out_dir="$TEST_DIR/coverage"
  COVERAGE_DIR="$out_dir" run "$DOTFILES_DIR/bin/dotfiles-coverage" run tests/cheat.bats
  [ "$status" -eq 0 ]
  [ -f "$out_dir/bats/coverage.json" ]
  total="$(jq -r '.total_lines' "$out_dir/bats/coverage.json")"
  covered="$(jq -r '.covered_lines' "$out_dir/bats/coverage.json")"
  [ "$total" -gt 0 ]
  [ "$covered" -gt 0 ]
}

@test "coverage report denominator covers every maintained shell surface" {
  # Without this, expanding `make lint` to a new shell directory could
  # silently leave that directory uninstrumented while the floor still
  # passes — exactly the gap that motivated this task.
  out_dir="$TEST_DIR/coverage"
  COVERAGE_DIR="$out_dir" run "$DOTFILES_DIR/bin/dotfiles-coverage" run tests/cheat.bats
  [ "$status" -eq 0 ]
  [ -f "$out_dir/bats/coverage.json" ]

  files="$(jq -r '.files[].file' "$out_dir/bats/coverage.json")"

  # Directory-prefix surfaces (one rep file per surface to keep the test
  # tolerant of new files landing under each directory).
  echo "$files" | grep -Eq '^bin/'              || { echo "bin/ missing"; return 1; }
  echo "$files" | grep -Eq '^lib/'              || { echo "lib/ missing"; return 1; }
  echo "$files" | grep -Eq '^modules/'          || { echo "modules/ missing"; return 1; }
  echo "$files" | grep -Eq '^\.chezmoiscripts/' || { echo ".chezmoiscripts/ missing"; return 1; }
  echo "$files" | grep -Eq '^\.github/scripts/' || { echo ".github/scripts/ missing"; return 1; }
  echo "$files" | grep -Eq '^git-hooks/'        || { echo "git-hooks/ missing"; return 1; }

  # Single-file prefixes — anchor to exact name so we know the
  # file-vs-directory dispatch in discover_source_files works.
  echo "$files" | grep -Fxq 'macos.sh'        || { echo "macos.sh missing"; return 1; }
  echo "$files" | grep -Fxq 'macos-visual.sh' || { echo "macos-visual.sh missing"; return 1; }
  echo "$files" | grep -Fxq 'macos-apps.sh'   || { echo "macos-apps.sh missing"; return 1; }
  echo "$files" | grep -Fxq 'snapshot.sh'     || { echo "snapshot.sh missing"; return 1; }
}

@test "coverage report excludes chezmoi *.sh.tmpl templates" {
  # `make lint` uses `wildcard .chezmoiscripts/*.sh` (not `*.sh.tmpl`),
  # because chezmoi renders templates into temp files at apply time and
  # the runtime path is the rendered content. Coverage discovery must
  # match — otherwise the denominator inflates with template sources
  # that can never be exercised in their on-disk form.
  out_dir="$TEST_DIR/coverage"
  COVERAGE_DIR="$out_dir" run "$DOTFILES_DIR/bin/dotfiles-coverage" run tests/cheat.bats
  [ "$status" -eq 0 ]

  files="$(jq -r '.files[].file' "$out_dir/bats/coverage.json")"
  ! echo "$files" | grep -Eq '\.tmpl$' || { echo "*.tmpl files leaked into coverage report"; return 1; }
}

@test "coverage floor is defined in one repo-local file" {
  grep -Eq '^[0-9]+([.][0-9]+)?$' "$COVERAGE_FLOOR"
}

@test "coverage floor is a measured ratchet, not a placeholder" {
  floor="$(sed -n '1p' "$COVERAGE_FLOOR")"
  awk -v floor="$floor" 'BEGIN { exit !(floor + 0 >= 10 && floor + 0 < 100) }'
}

@test "make coverage enforces the shared coverage floor" {
  run coverage_make_target
  [ "$status" -eq 0 ]
  [[ "$output" == *".github/scripts/check-shell-coverage.sh coverage/bats/coverage.json .shell-coverage-floor"* ]]
}

@test "coverage helper fails below the floor" {
  mkdir -p "$TEST_DIR"
  cat > "$TEST_DIR/coverage.json" <<'JSON'
{"percent_covered": 0}
JSON

  run "$COVERAGE_CHECK" "$TEST_DIR/coverage.json" "$COVERAGE_FLOOR"
  [ "$status" -ne 0 ]
  [[ "$output" == *"below the"*"floor"* ]]
}

@test "coverage helper passes at the floor" {
  mkdir -p "$TEST_DIR"
  floor="$(sed -n '1p' "$COVERAGE_FLOOR")"
  cat > "$TEST_DIR/coverage.json" <<JSON
{"percent_covered": $floor}
JSON

  run "$COVERAGE_CHECK" "$TEST_DIR/coverage.json" "$COVERAGE_FLOOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Coverage floor satisfied"* ]]
}

@test "CI coverage job does not ignore tracer or bats failures" {
  run coverage_workflow_step
  [ "$status" -eq 0 ]
  [[ "$output" == *"bin/dotfiles-coverage run"* ]]
  [[ "$output" != *"|| true"* ]]
}

@test "CI coverage artifacts still upload after failures" {
  grep -A2 'name: Upload coverage report' "$CI_WORKFLOW" | grep -q 'if: always()'
}

@test "CI coverage extraction fails when no report is written" {
  awk '
    /Coverage report not found/ { saw_missing_report = 1 }
    saw_missing_report && /exit 1/ { saw_exit = 1 }
    END { exit !(saw_missing_report && saw_exit) }
  ' "$CI_WORKFLOW"
}

@test "CI coverage extraction enforces the shared coverage floor" {
  awk '
    /floor=\$\(sed -n '\''1p'\'' .shell-coverage-floor\)/ { saw_floor = 1 }
    /\.github\/scripts\/check-shell-coverage\.sh coverage\/bats\/coverage\.json \.shell-coverage-floor/ { saw_check = 1 }
    END { exit !(saw_floor && saw_check) }
  ' "$CI_WORKFLOW"
}

@test "CI docs explain the coverage floor workflow" {
  grep -Fq '.shell-coverage-floor' "$DOTFILES_DIR/docs/ci-setup.md"
  grep -Fq 'make coverage' "$DOTFILES_DIR/docs/ci-setup.md"
  grep -Fq 'measured ratchet' "$DOTFILES_DIR/docs/ci-setup.md"
  grep -Fq 'raise the floor' "$DOTFILES_DIR/docs/ci-setup.md"
}

@test "README documents the coverage floor ratchet" {
  grep -Fq '.shell-coverage-floor' "$DOTFILES_DIR/README.md"
  grep -Fq 'latest full `make coverage`' "$DOTFILES_DIR/README.md"
  grep -Fq '1.0 point buffer' "$DOTFILES_DIR/README.md"
}

# ── Focused edge-case tests for the trace-based coverage stack ────
#
# The tests above exercise the harness end-to-end via bats. The cases
# below feed synthetic traces and stub source trees directly into
# lib/coverage-report.py and lib/coverage-trap.sh so failure paths can
# be probed cheaply without re-running a full bats suite.

write_synthetic_source() {
  # Build a stub shell file with a known executable-line count.
  # `.sh` extension is enough to satisfy `_qualifies_as_shell` without
  # adding a shebang (which would skew the executable-line denominator).
  local path="$1" lines="$2"
  mkdir -p "$(dirname "$path")"
  : > "$path"
  for ((i = 1; i <= lines; i++)); do
    printf 'echo line %d\n' "$i" >> "$path"
  done
}

run_coverage_report_py() {
  local trace_dir="$1" repo_root="$2" output="$3"
  shift 3
  python3 "$DOTFILES_DIR/lib/coverage-report.py" \
    --trace-dir "$trace_dir" \
    --repo-root "$repo_root" \
    --output "$output" \
    --include "$@"
}

@test "coverage-trap: re-sourcing in same PID does not reinstall the trap" {
  # The guard compares against $$ rather than a plain set/unset flag, so
  # subshells inherit instrumentation but a second `source` in the same
  # process is a no-op. If this regresses, every nested bash subshell
  # would re-run the install — opening a fresh fd 99 each time and
  # silently leaking file descriptors during long bats runs.
  trace_dir="$TEST_DIR/trace"
  log="$TEST_DIR/probe.log"
  mkdir -p "$trace_dir"

  COVERAGE_TRACE_DIR="$trace_dir" bash -c "
    source '$DOTFILES_DIR/lib/coverage-trap.sh'
    first=\$_DOTFILES_COVERAGE_INSTALLED_PID
    source '$DOTFILES_DIR/lib/coverage-trap.sh'
    second=\$_DOTFILES_COVERAGE_INSTALLED_PID
    printf 'first=%s second=%s pid=%s\n' \"\$first\" \"\$second\" \"\$\$\" > '$log'
  "

  run cat "$log"
  [ "$status" -eq 0 ]
  pid="$(awk -F= '{print $4}' "$log")"
  first="$(awk -F'[ =]' '{print $2}' "$log")"
  second="$(awk -F'[ =]' '{print $4}' "$log")"
  [ "$first" = "$pid" ]
  [ "$second" = "$pid" ]
}

@test "coverage-trap: no-op when COVERAGE_TRACE_DIR is unset" {
  # The harness must not enable xtrace globally. Sourcing the helper in a
  # plain shell (no COVERAGE_TRACE_DIR) should leave `set -x` off so users
  # invoking `bats` directly don't get a flood of xtrace output.
  log="$TEST_DIR/noop.log"
  env -u BASH_ENV -u COVERAGE_TRACE_DIR bash -c "
    unset COVERAGE_TRACE_DIR
    source '$DOTFILES_DIR/lib/coverage-trap.sh'
    case \$- in
      *x*) printf 'xtrace=on\n' ;;
      *)   printf 'xtrace=off\n' ;;
    esac
  " > "$log"

  [ "$(cat "$log")" = "xtrace=off" ]
}

@test "coverage-trap: legacy bash does not leak xtrace to stderr" {
  [ -x /bin/bash ] || skip "/bin/bash is not available"
  /bin/bash -c '
    [ "${BASH_VERSINFO[0]}" -lt 4 ] ||
      { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -lt 1 ]; }
  ' || skip "/bin/bash supports BASH_XTRACEFD"

  trace_dir="$TEST_DIR/legacy-trace"
  out="$TEST_DIR/legacy.out"
  mkdir -p "$trace_dir"

  COVERAGE_TRACE_DIR="$trace_dir" BASH_ENV="$DOTFILES_DIR/lib/coverage-trap.sh" \
    /bin/bash -c 'echo legacy-ok' > "$out" 2>&1

  [ "$(cat "$out")" = "legacy-ok" ]
}

@test "coverage-report: parses COV@file@line@ markers from a synthetic trace" {
  trace_dir="$TEST_DIR/trace"
  repo="$TEST_DIR/repo"
  mkdir -p "$trace_dir" "$repo/bin"
  write_synthetic_source "$repo/bin/sample.sh" 5

  # Mix legitimate markers with the leading-noise variant the regex
  # comment in coverage-report.py specifically calls out (`CCOV@…`).
  cat > "$trace_dir/trace.111.log" <<TRACE
COV@bin/sample.sh@1@echo line 1
COV@bin/sample.sh@3@echo line 3
some unrelated noise without a marker
CCOV@bin/sample.sh@4@echo line 4
TRACE

  run_coverage_report_py "$trace_dir" "$repo" "$TEST_DIR/cov.json" "bin/"
  [ -f "$TEST_DIR/cov.json" ]
  hit="$(jq -r '.files[] | select(.file == "bin/sample.sh") | .covered_lines' "$TEST_DIR/cov.json")"
  total="$(jq -r '.files[] | select(.file == "bin/sample.sh") | .total_lines' "$TEST_DIR/cov.json")"
  [ "$hit" = "3" ]
  [ "$total" = "5" ]
}

@test "coverage-report: drops malformed lines and out-of-range line numbers" {
  trace_dir="$TEST_DIR/trace"
  repo="$TEST_DIR/repo"
  mkdir -p "$trace_dir" "$repo/bin"
  write_synthetic_source "$repo/bin/sample.sh" 3

  # Garbage trace entries (no marker, empty source slot, line beyond
  # file end, non-numeric line, unrelated path) must not crash the
  # parser or inflate the covered count.
  cat > "$trace_dir/trace.222.log" <<TRACE
this line has no marker at all
COV@@1@bash -c snippet
COV@bin/sample.sh@99999@echo missing
COV@bin/sample.sh@notanumber@echo bad
COV@/etc/passwd@1@echo outside repo
COV@bin/sample.sh@2@echo line 2
TRACE

  run_coverage_report_py "$trace_dir" "$repo" "$TEST_DIR/cov.json" "bin/"
  [ -f "$TEST_DIR/cov.json" ]
  hit="$(jq -r '.files[] | select(.file == "bin/sample.sh") | .covered_lines' "$TEST_DIR/cov.json")"
  [ "$hit" = "1" ]
  # Out-of-repo path should not appear in the report at all.
  ! jq -r '.files[].file' "$TEST_DIR/cov.json" | grep -q '^/etc/'
}

@test "coverage-report: discovers extension-less bash scripts via shebang" {
  trace_dir="$TEST_DIR/trace"
  repo="$TEST_DIR/repo"
  mkdir -p "$trace_dir" "$repo/bin"

  # Extension-less bash script (`bin/foo`) should be discovered; a
  # similarly extension-less but non-bash file should not.
  cat > "$repo/bin/foo" <<'BASH'
#!/usr/bin/env bash
echo hi
echo there
BASH
  chmod +x "$repo/bin/foo"
  cat > "$repo/bin/note" <<'TEXT'
just a text file with no shebang
TEXT
  : > "$trace_dir/trace.333.log"

  run_coverage_report_py "$trace_dir" "$repo" "$TEST_DIR/cov.json" "bin/"
  files="$(jq -r '.files[].file' "$TEST_DIR/cov.json")"
  echo "$files" | grep -Fxq 'bin/foo'
  ! echo "$files" | grep -Fxq 'bin/note'
}

@test "coverage-report: returns a zeroed report for an empty trace dir" {
  # An empty trace dir must not crash the report — `dotfiles-coverage`
  # promotes a non-empty file to a successful run, and the JSON is
  # consumed by check-shell-coverage.sh which expects `percent_covered`.
  trace_dir="$TEST_DIR/empty-trace"
  repo="$TEST_DIR/repo"
  mkdir -p "$trace_dir" "$repo/bin"
  write_synthetic_source "$repo/bin/sample.sh" 2

  run_coverage_report_py "$trace_dir" "$repo" "$TEST_DIR/cov.json" "bin/"
  [ -f "$TEST_DIR/cov.json" ]
  pct="$(jq -r '.percent_covered' "$TEST_DIR/cov.json")"
  total="$(jq -r '.total_lines' "$TEST_DIR/cov.json")"
  [ "$pct" = "0.00" ]
  [ "$total" -ge 2 ]
}

@test "dotfiles-coverage report: fails clearly when the trace dir is missing" {
  cov_dir="$TEST_DIR/coverage-missing"
  # Deliberately do not create $cov_dir/trace.
  COVERAGE_DIR="$cov_dir" run "$DOTFILES_DIR/bin/dotfiles-coverage" report
  [ "$status" -ne 0 ]
  [[ "$output" == *"No trace directory"* ]]
  [[ "$output" == *"dotfiles-coverage run"* ]]
}

@test "dotfiles-coverage run: writes a report even when bats fails" {
  cov_dir="$TEST_DIR/coverage-failing"
  failing_dir="$TEST_DIR/failing-tests"
  mkdir -p "$failing_dir"
  cat > "$failing_dir/fail.bats" <<'BATS'
#!/usr/bin/env bats
@test "intentional failure" {
  false
}
BATS

  # Run from a temp working dir so the harness instruments only the
  # stub failing test; we still want it to produce coverage.json and
  # propagate the non-zero bats exit.
  COVERAGE_DIR="$cov_dir" run "$DOTFILES_DIR/bin/dotfiles-coverage" run "$failing_dir/fail.bats"
  [ "$status" -ne 0 ]
  [ -f "$cov_dir/bats/coverage.json" ]
  [[ "$output" == *"Tests failed"* ]]
  [[ "$output" == *"coverage report still written"* ]]
}

#!/usr/bin/env bats
# bats --jobs needs GNU parallel, which the core Brewfile does not install.
# Without `parallel` on PATH, the make test targets must run bats serially.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  FAKE_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$FAKE_BIN"
}

_make_dry_run() {
  PATH="$1" make -C "$REPO_ROOT" -n --no-print-directory "$2"
}

@test "make test targets run bats serially when parallel is missing" {
  for target in test test-all test-force; do
    run _make_dry_run "$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" "$target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"bats"* ]]
    [[ "$output" != *"--jobs"* ]]
  done
}

@test "make test targets use bats --jobs when parallel is on PATH" {
  printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/parallel"
  chmod +x "$FAKE_BIN/parallel"
  for target in test test-all test-force; do
    run _make_dry_run "$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" "$target"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--jobs"* ]]
  done
}

@test "CONTRIBUTING documents the serial fallback without parallel" {
  grep -q 'serial' "$REPO_ROOT/CONTRIBUTING.md"
  grep -q 'parallel' "$REPO_ROOT/CONTRIBUTING.md"
}

# Wall-clock budgets are not meaningful on a saturated host (for example
# under `bats --jobs`). host_is_saturated lets timing tests skip there.
@test "host_is_saturated is true when the 1-minute load exceeds the CPU count" {
  load test_helper
  DOTFILES_TEST_LOAD1=99 DOTFILES_TEST_NCPU=8 run host_is_saturated
  [ "$status" -eq 0 ]
  DOTFILES_TEST_LOAD1=3 DOTFILES_TEST_NCPU=8 run host_is_saturated
  [ "$status" -ne 0 ]
}

@test "the doctor timing test skips instead of failing on a saturated host" {
  grep -q 'host_is_saturated' "$REPO_ROOT/tests/doctor.bats"
}

_scheduler_fixture() {
  local target="$1" selection="${2:-all}" parallel_mode="${3:-parallel}"
  SCHED_REPO="$BATS_TEST_TMPDIR/repo-$target"
  SCHED_STATE="$BATS_TEST_TMPDIR/state-$target"
  mkdir -p "$SCHED_REPO/bin" "$SCHED_REPO/tests/plugin" "$SCHED_STATE/home"
  SCHED_REPO="$(cd "$SCHED_REPO" && pwd -P)"
  cp "$REPO_ROOT/Makefile" "$SCHED_REPO/Makefile"
  cp "$REPO_ROOT/.tasks-lint-version" "$SCHED_REPO/.tasks-lint-version"
  cp "$REPO_ROOT/bin/cached-run" "$SCHED_REPO/bin/cached-run"
  : > "$SCHED_STATE/selected"
  : > "$SCHED_STATE/peers"
  : > "$SCHED_STATE/events"
  : > "$SCHED_STATE/bats-args"
  if [ "$selection" != doctor ]; then
    for file in tests/a-peer.bats tests/plugin/z-peer.bats; do
      printf '# fixture %s\n' "$file" > "$SCHED_REPO/$file"
      printf '%s\n' "$file" >> "$SCHED_STATE/selected"
      printf '%s\n' "$file" >> "$SCHED_STATE/peers"
    done
  fi
  if [ "$selection" != peers ]; then
    printf '# fixture doctor\n' > "$SCHED_REPO/tests/doctor.bats"
    printf 'tests/doctor.bats\n' >> "$SCHED_STATE/selected"
  fi
  cat > "$SCHED_REPO/bin/bats-affected" <<'STUB'
#!/bin/bash
repo="$(cd "$(dirname "$0")/.." && pwd)"
while IFS= read -r file; do
  if [ "${SCHEDULER_RELATIVE:-false}" = true ]; then
    printf '%s\tMakefile\n' "$file"
  else
    printf '%s/%s\tMakefile\n' "$repo" "$file"
  fi
done < "$SCHEDULER_STATE/selected"
STUB
  cat > "$FAKE_BIN/bats" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$SCHEDULER_STATE/bats-args"
files=()
jobs=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --jobs|-j) jobs="$2"; shift 2 ;;
    --no-parallelize-within-files) shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done
for path in "$@"; do
  if [ -d "$path" ]; then
    for file in "${path%/}"/*.bats; do [ ! -f "$file" ] || files+=("$file"); done
  else
    files+=("$path")
  fi
done
_run_file() {
  local file="${1#"$SCHEDULER_REPO/"}" result=0 peer
  printf 'start %s\n' "$file" >> "$SCHEDULER_STATE/events"
  if [ "$file" = tests/doctor.bats ]; then
    while IFS= read -r peer; do
      if [ ! -f "$SCHEDULER_STATE/done/$peer" ]; then
        printf 'overlap %s\n' "$peer" >> "$SCHEDULER_STATE/events"
        result=31
      fi
    done < "$SCHEDULER_STATE/peers"
  else
    /bin/sleep 0.05
  fi
  mkdir -p "$SCHEDULER_STATE/done/$(dirname "$file")"
  touch "$SCHEDULER_STATE/done/$file"
  printf 'end %s\n' "$file" >> "$SCHEDULER_STATE/events"
  [ "$file" != "${SCHEDULER_FAIL_FILE:-}" ] || result=23
  return "$result"
}
result=0
if [ "$jobs" -gt 1 ]; then
  pids=()
  for file in "${files[@]}"; do _run_file "$file" & pids+=("$!"); done
  for pid in "${pids[@]}"; do wait "$pid" || result=$?; done
else
  for file in "${files[@]}"; do _run_file "$file" || result=$?; done
fi
exit "$result"
STUB
  chmod +x "$FAKE_BIN/bats" "$SCHED_REPO/bin/bats-affected" "$SCHED_REPO/bin/cached-run"
  if [ "$parallel_mode" = parallel ]; then
    printf '#!/bin/bash\nexit 0\n' > "$FAKE_BIN/parallel"
    chmod +x "$FAKE_BIN/parallel"
  fi
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" init -q
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" config user.name 'Test User'
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" config user.email test@example.com
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" config core.hooksPath /dev/null
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" add Makefile bin/cached-run bin/bats-affected
  while IFS= read -r file; do GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" add "$file"; done < "$SCHED_STATE/selected"
  GIT_CONFIG_GLOBAL=/dev/null git -C "$SCHED_REPO" commit -qm 'chore: scheduler fixture'
}

_scheduler_make() {
  env -u BASH_ENV -u ENV HOME="$SCHED_STATE/home" GIT_CONFIG_GLOBAL=/dev/null \
    PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" CACHED_RUN_DIR="$SCHED_STATE/cache" \
    SCHEDULER_RELATIVE="${SCHEDULER_RELATIVE:-false}" \
    SCHEDULER_STATE="$SCHED_STATE" SCHEDULER_REPO="$SCHED_REPO" SCHEDULER_FAIL_FILE="${SCHEDULER_FAIL_FILE:-}" \
    make -C "$SCHED_REPO" --no-print-directory "$1" JOBS=2 FULLPOWER=
}

_scheduler_exact_coverage() {
  local file
  while IFS= read -r file; do
    [ "$(grep -cFx "end $file" "$SCHED_STATE/events")" -eq 1 ] || return 1
  done < "$SCHED_STATE/selected"
  [ "$(grep -c '^end ' "$SCHED_STATE/events")" -eq "$(wc -l < "$SCHED_STATE/selected" | tr -d ' ')" ] || return 1
  ! grep -q '^overlap ' "$SCHED_STATE/events"
}

@test "actual make recipes finish peers before running doctor exactly once" {
  local failed=0
  for target in test test-all test-force; do
    _scheduler_fixture "$target"
    run _scheduler_make "$target"
    if [ "$status" -ne 0 ]; then echo "$target: $output"; failed=1; fi
    _scheduler_exact_coverage || failed=1
  done
  [ "$failed" -eq 0 ]
}

@test "actual make recipes preserve doctor-only selection" {
  for target in test test-all test-force; do
    _scheduler_fixture "$target" doctor
    run _scheduler_make "$target"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    _scheduler_exact_coverage
  done
}

@test "actual make recipes preserve selections without doctor including plugin tests" {
  for target in test test-all test-force; do
    _scheduler_fixture "$target" peers
    run _scheduler_make "$target"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    _scheduler_exact_coverage
  done
}

@test "actual make recipes propagate peer failure and still run every selected file" {
  for target in test test-all test-force; do
    _scheduler_fixture "$target"
    SCHEDULER_FAIL_FILE=tests/a-peer.bats
    run _scheduler_make "$target"
    [ "$status" -ne 0 ]
    _scheduler_exact_coverage
  done
}

@test "actual make recipes propagate doctor failure after peers complete" {
  for target in test test-all test-force; do
    _scheduler_fixture "$target"
    SCHEDULER_FAIL_FILE=tests/doctor.bats
    run _scheduler_make "$target"
    [ "$status" -ne 0 ]
    _scheduler_exact_coverage
  done
}

@test "actual make recipes keep the isolated doctor order without GNU parallel" {
  for target in test test-all test-force; do
    _scheduler_fixture "$target" all serial
    run _scheduler_make "$target"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    _scheduler_exact_coverage
    ! grep -q -- '--jobs' "$SCHED_STATE/bats-args"
  done
}

@test "actual cached make recipes reuse a successful peer and doctor run" {
  for target in test test-all; do
    _scheduler_fixture "$target"
    run _scheduler_make "$target"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    _scheduler_exact_coverage
    run _scheduler_make "$target"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    _scheduler_exact_coverage
    [ -d "$SCHED_STATE/cache" ]
  done
}


@test "affected scheduler also accepts relative selector paths" {
  _scheduler_fixture test
  SCHEDULER_RELATIVE=true
  run _scheduler_make test
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _scheduler_exact_coverage
}

@test "scheduler coverage oracle rejects unexpected extra files" {
  _scheduler_fixture test doctor
  run _scheduler_make test
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  _scheduler_exact_coverage
  printf 'end tests/unselected.bats\n' >> "$SCHED_STATE/events"
  run _scheduler_exact_coverage
  [ "$status" -ne 0 ]
}

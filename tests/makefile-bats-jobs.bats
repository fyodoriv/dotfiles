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

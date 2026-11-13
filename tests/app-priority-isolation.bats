#!/usr/bin/env bats

@test "app-priority tests leave inherited configuration untouched" {
  local scratch="$BATS_TEST_TMPDIR/isolation"
  local bats_bin="$BATS_ROOT/bin/bats"
  [[ "$bats_bin" = /* ]]
  [ -x "$bats_bin" ]
  local child_path="$(dirname "$bats_bin"):/usr/bin:/bin:/usr/sbin:/sbin"
  mkdir -p "$scratch/home" "$scratch/xdg/dotfiles" "$scratch/tmp"
  printf 'fixture-canary\n' > "$scratch/expected"
  cp "$scratch/expected" "$scratch/xdg/dotfiles/priority-apps.txt"

  run env -i HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/xdg" TMPDIR="$scratch/tmp" PATH="$child_path" \
    "$bats_bin" -f '^no such app-priority test$' "$BATS_TEST_DIRNAME/app-priority.bats"
  [[ "$output" != *'ok 1 app-priority runs without errors using defaults'* ]]

  run env -i HOME="$scratch/home" XDG_CONFIG_HOME="$scratch/xdg" TMPDIR="$scratch/tmp" PATH="$child_path" \
    "$bats_bin" -f '^app-priority runs without errors using defaults$' "$BATS_TEST_DIRNAME/app-priority.bats"
  [ "$status" -eq 0 ]
  [[ "$output" == $'1..1\nok 1 app-priority runs without errors using defaults' ]]
  cmp "$scratch/expected" "$scratch/xdg/dotfiles/priority-apps.txt"
}

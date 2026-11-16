#!/usr/bin/env bats
# `dotfiles apply` rebuilds the opt-in native app-priority when its source changes.

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/.chezmoiscripts/run_onchange_after_app-priority-native.sh.tmpl"

@test "the apply script hashes every app-priority Rust source file" {
  local f rel
  for f in "$ROOT"/rust/app-priority/Cargo.toml "$ROOT"/rust/app-priority/Cargo.lock "$ROOT"/rust/app-priority/src/*.rs; do
    rel="${f#"$ROOT"/}"
    grep -qF "include \"$rel\" | sha256sum" "$SCRIPT" || { echo "not hashed: $rel"; return 1; }
  done
}

@test "the apply script does nothing on a Mac without the native install" {
  sed 's/{{[^}]*}}//g' "$SCRIPT" > "$BATS_TEST_TMPDIR/refresh.sh"
  XDG_DATA_HOME="$BATS_TEST_TMPDIR/empty" run bash "$BATS_TEST_TMPDIR/refresh.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a failed rebuild keeps apply going and names the retry command" {
  mkdir -p "$BATS_TEST_TMPDIR/src/bin" "$BATS_TEST_TMPDIR/data/dotfiles/native/app-priority"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/src/bin/app-priority-native"
  ln -s app-priority-x "$BATS_TEST_TMPDIR/data/dotfiles/native/app-priority/current"
  sed -e "s|{{ .chezmoi.sourceDir }}|$BATS_TEST_TMPDIR/src|g" -e 's/{{[^}]*}}//g' "$SCRIPT" > "$BATS_TEST_TMPDIR/refresh.sh"
  XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" run bash "$BATS_TEST_TMPDIR/refresh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous build stays active"* ]]
  [[ "$output" == *"dotfiles priority-native install"* ]]
}

@test "a successful rebuild runs the install command" {
  mkdir -p "$BATS_TEST_TMPDIR/src/bin" "$BATS_TEST_TMPDIR/data/dotfiles/native/app-priority"
  # shellcheck disable=SC2016  # $1 belongs to the fake installer
  printf '#!/bin/bash\necho "ran $1"\n' > "$BATS_TEST_TMPDIR/src/bin/app-priority-native"
  ln -s app-priority-x "$BATS_TEST_TMPDIR/data/dotfiles/native/app-priority/current"
  sed -e "s|{{ .chezmoi.sourceDir }}|$BATS_TEST_TMPDIR/src|g" -e 's/{{[^}]*}}//g' "$SCRIPT" > "$BATS_TEST_TMPDIR/refresh.sh"
  XDG_DATA_HOME="$BATS_TEST_TMPDIR/data" run bash "$BATS_TEST_TMPDIR/refresh.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran install"* ]]
}

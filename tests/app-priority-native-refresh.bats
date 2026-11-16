#!/usr/bin/env bats
# `dotfiles apply` rebuilds the opt-in native app-priority when its source changes.
# shellcheck disable=SC2016  # fake installers expand $1 when they run

ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/.chezmoiscripts/run_after_app-priority-native.sh.tmpl"

setup() {
  SRC="$BATS_TEST_TMPDIR/src"
  DATA="$BATS_TEST_TMPDIR/data"
  NATIVE="$DATA/dotfiles/native/app-priority"
  mkdir -p "$SRC/bin" "$NATIVE"
  sed -e "s|{{ .chezmoi.sourceDir }}|$SRC|g" -e 's/{{[^}]*}}/H/g' "$SCRIPT" > "$BATS_TEST_TMPDIR/refresh.sh"
}

fake_installer() {
  printf '#!/bin/bash\n%s\n' "$1" > "$SRC/bin/app-priority-native"
}

refresh() {
  XDG_DATA_HOME="$DATA" DOTFILES_NATIVE_BUILD_MAX_WAIT="${1:-30}" run bash "$BATS_TEST_TMPDIR/refresh.sh"
}

@test "the apply script hashes every app-priority crate file" {
  local f rel
  while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    grep -qF "include \"$rel\" | sha256sum" "$SCRIPT" || { echo "not hashed: $rel"; return 1; }
  done < <(git -C "$ROOT" ls-files --full-name rust/.cargo rust/app-priority \
    | grep -v '/\.gitignore$' | sed "s|^|$ROOT/|")
}

@test "the apply script does nothing on a Mac without the native install" {
  fake_installer 'echo "ran $1"'
  refresh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a good rebuild records the source hash and the next apply skips it" {
  fake_installer 'echo "ran $1"'
  ln -s app-priority-x "$NATIVE/current"
  refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ran install"* ]]
  [ -f "$NATIVE/source-hash" ]
  refresh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a failed rebuild keeps apply going and is retried on the next apply" {
  fake_installer 'echo "ran $1"; exit 1'
  ln -s app-priority-x "$NATIVE/current"
  refresh
  [ "$status" -eq 0 ]
  [[ "$output" == *"rebuild failed; the previous build stays active"* ]]
  [[ "$output" == *"dotfiles priority-native install"* ]]
  [ ! -f "$NATIVE/source-hash" ]
  refresh
  [[ "$output" == *"ran install"* ]]
}

@test "a build stuck waiting for a slot stops after the time limit" {
  fake_installer 'sleep 20 & wait'
  ln -s app-priority-x "$NATIVE/current"
  refresh 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"timed out after 1s"* ]]
  [ ! -f "$NATIVE/source-hash" ]
}

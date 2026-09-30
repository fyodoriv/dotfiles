#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  STUB_HB="$TEST_DIR/stubs/opt/homebrew"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/lib" "$STUB_HB/bin"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/"
  for g in gfind gsed gawk ggrep; do
    cp /bin/echo "$STUB_HB/bin/$g"
    chmod +x "$STUB_HB/bin/$g"
    codesign --sign - --force "$STUB_HB/bin/$g" >/dev/null 2>&1 || true
  done
  export HOME="$TEST_HOME"
  export DOTFILES_BREW_PREFIX="$STUB_HB"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "homebrew gnu sandbox aliases: find resolves on sandbox PATH" {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-homebrew-gnu-sandbox-aliases" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  run env DOTFILES_BREW_PREFIX="$STUB_HB" "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  [ "$status" -eq 0 ]
  run env PATH="$STUB_HB/bin:/usr/bin:/bin" command -v find
  [ "$status" -eq 0 ]
  [[ "$output" == "$STUB_HB/bin/find" ]]
  [[ "$(readlink "$STUB_HB/bin/find")" == "gfind" ]]
}

@test "homebrew gnu sandbox aliases: curl keg resolves on sandbox PATH" {
  mkdir -p "$STUB_HB/opt/curl/bin"
  cp /bin/echo "$STUB_HB/opt/curl/bin/curl"
  chmod +x "$STUB_HB/opt/curl/bin/curl"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-homebrew-gnu-sandbox-aliases" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  run env PATH="$STUB_HB/bin:/usr/bin:/bin" command -v curl
  [ "$status" -eq 0 ]
  [[ "$output" == "$STUB_HB/bin/curl" ]]
}

@test "homebrew gnu sandbox aliases: sed/awk/grep resolve on sandbox PATH" {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-homebrew-gnu-sandbox-aliases" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  for tool in sed awk grep; do
    run env PATH="$STUB_HB/bin:/usr/bin:/bin" command -v "$tool"
    [ "$status" -eq 0 ]
    [[ "$output" == "$STUB_HB/bin/$tool" ]]
  done
}

@test "homebrew gnu sandbox aliases: idempotent curl link does not refresh mtime" {
  mkdir -p "$STUB_HB/opt/curl/bin"
  cp /bin/echo "$STUB_HB/opt/curl/bin/curl"
  chmod +x "$STUB_HB/opt/curl/bin/curl"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-homebrew-gnu-sandbox-aliases" "$TEST_DOTFILES/bin/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  [ -L "$STUB_HB/bin/curl" ]
  # Freeze mtime, re-run, assert inode/mtime unchanged (no ln -sfn churn → endpoint agent install spam)
  touch -t 202001011200.00 "$STUB_HB/bin/curl"
  before_mtime="$(stat -f '%m' "$STUB_HB/bin/curl")"
  before_inode="$(stat -f '%i' "$STUB_HB/bin/curl")"
  run env DOTFILES_BREW_PREFIX="$STUB_HB" DOTFILES_ADHOC_SIGN_QUIET=0 \
    "$TEST_DOTFILES/bin/dotfiles-link-homebrew-gnu-sandbox-aliases"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already linked: $STUB_HB/bin/curl"* ]]
  [ "$(stat -f '%m' "$STUB_HB/bin/curl")" = "$before_mtime" ]
  [ "$(stat -f '%i' "$STUB_HB/bin/curl")" = "$before_inode" ]
  [[ "$(readlink "$STUB_HB/bin/curl")" == "../opt/curl/bin/curl" ]]
}

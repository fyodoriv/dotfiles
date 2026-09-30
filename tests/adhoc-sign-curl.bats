#!/usr/bin/env bats
# Tests for bin/dotfiles-adhoc-sign-curl (binary + libcurl dylib).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  STUB_HB="$TEST_DIR/opt/homebrew"
  CURL_KEG="$STUB_HB/Cellar/curl/8.21.0"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/lib" \
    "$CURL_KEG/bin" "$CURL_KEG/lib" "$STUB_HB/opt/curl/bin" "$STUB_HB/opt/curl/lib"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_BREW_PREFIX="$STUB_HB"
  export DOTFILES_ADHOC_SIGN_QUIET=1

  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-curl" "$TEST_DOTFILES/bin/"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl"

  # Real Mach-O stubs so codesign + file(1) behave.
  cp /bin/echo "$CURL_KEG/bin/curl"
  cp /bin/echo "$CURL_KEG/lib/libcurl.4.dylib"
  chmod 755 "$CURL_KEG/bin/curl"
  chmod 444 "$CURL_KEG/lib/libcurl.4.dylib"   # real libcurl is mode 444
  # Absolute symlinks — relative ../../ from opt/curl/bin misses Cellar.
  ln -sfn "$CURL_KEG/bin/curl" "$STUB_HB/opt/curl/bin/curl"
  ln -sfn "$CURL_KEG/lib/libcurl.4.dylib" "$STUB_HB/opt/curl/lib/libcurl.4.dylib"
  codesign --remove-signature "$CURL_KEG/bin/curl" >/dev/null 2>&1 || true
  codesign --remove-signature "$CURL_KEG/lib/libcurl.4.dylib" >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "adhoc-sign-curl: signs curl binary" {
  run "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl"
  [ "$status" -eq 0 ]
  codesign -dvv "$CURL_KEG/bin/curl" 2>&1 | grep -q "Signature=adhoc"
}

@test "adhoc-sign-curl: signs mode-444 libcurl.4.dylib" {
  run "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-curl"
  [ "$status" -eq 0 ]
  codesign -dvv "$CURL_KEG/lib/libcurl.4.dylib" 2>&1 | grep -q "Signature=adhoc"
}

@test "adhoc-sign-curl: documents libcurl companion scope" {
  grep -q 'libcurl' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-curl"
  grep -q 'mode 444' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-curl" || \
    grep -q 'no +x' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-curl"
}

@test "adhoc-sign-bottles: documents non-exec dylib scope" {
  grep -q '\.dylib' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-bottles"
  grep -q 'libcurl' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-bottles"
}

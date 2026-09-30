#!/usr/bin/env bats
# Tests for bin/dotfiles-adhoc-sign-uv-pythons (interpreter + libpython/.so/.dylib).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  UV_ROOT="$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-x86_64-none"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/lib" \
    "$UV_ROOT/bin" "$UV_ROOT/lib/python3.13/lib-dynload"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_ADHOC_SIGN_QUIET=1

  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-uv-pythons" "$TEST_DOTFILES/bin/"
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/"
  chmod +x "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-uv-pythons"

  # Use real Mach-O stubs (copied /bin/echo) so codesign + file(1) behave.
  cp /bin/echo "$UV_ROOT/bin/python3.13"
  cp /bin/echo "$UV_ROOT/lib/libpython3.13.dylib"
  cp /bin/echo "$UV_ROOT/lib/python3.13/lib-dynload/_dbm.cpython-313-darwin.so"
  chmod +x "$UV_ROOT/bin/python3.13" "$UV_ROOT/lib/libpython3.13.dylib" \
    "$UV_ROOT/lib/python3.13/lib-dynload/_dbm.cpython-313-darwin.so"
  codesign --remove-signature "$UV_ROOT/bin/python3.13" >/dev/null 2>&1 || true
  codesign --remove-signature "$UV_ROOT/lib/libpython3.13.dylib" >/dev/null 2>&1 || true
  codesign --remove-signature "$UV_ROOT/lib/python3.13/lib-dynload/_dbm.cpython-313-darwin.so" >/dev/null 2>&1 || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "adhoc-sign-uv: signs python3.13 interpreter" {
  run "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-uv-pythons" "$TEST_HOME/.local/share/uv/python"
  [ "$status" -eq 0 ]
  codesign -dvv "$UV_ROOT/bin/python3.13" 2>&1 | grep -q "Signature=adhoc"
}

@test "adhoc-sign-uv: signs libpython3.13.dylib companion" {
  run "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-uv-pythons" "$TEST_HOME/.local/share/uv/python"
  [ "$status" -eq 0 ]
  codesign -dvv "$UV_ROOT/lib/libpython3.13.dylib" 2>&1 | grep -q "Signature=adhoc"
}

@test "adhoc-sign-uv: signs lib-dynload .so companions" {
  run "$TEST_DOTFILES/bin/dotfiles-adhoc-sign-uv-pythons" "$TEST_HOME/.local/share/uv/python"
  [ "$status" -eq 0 ]
  codesign -dvv "$UV_ROOT/lib/python3.13/lib-dynload/_dbm.cpython-313-darwin.so" 2>&1 | grep -q "Signature=adhoc"
}

@test "adhoc-sign-uv: script documents libpython companion scope" {
  grep -q 'libpython' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-uv-pythons"
  grep -q '\.dylib' "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-uv-pythons"
}

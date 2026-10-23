#!/usr/bin/env bats
# The plugin CLI runs on macOS /bin/bash 3.2 (its shebang). `make
# test-plugins-bash32` runs tests/plugin-update.bats and
# tests/plugin-v2.bats with tests/bash32/bash first on PATH, so every
# `bash` they start is /bin/bash. These cases prove that shim catches a
# construct bash 3.2 rejects.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHIM="$REPO/tests/bash32"
  [ -x /bin/bash ] || skip "needs /bin/bash"
  case "$(/bin/bash -c 'echo "$BASH_VERSION"')" in 3.*) ;; *) skip "/bin/bash is not bash 3.2" ;; esac
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/copy"
  cp -R "$REPO/bin" "$REPO/lib" "$TEST_DIR/copy/"
}

teardown() { [ -z "${TEST_DIR:-}" ] || rm -rf "$TEST_DIR"; }

@test "the shim makes bash on PATH /bin/bash 3.2" {
  [ -x "$SHIM/bash" ]
  run env PATH="$SHIM:$PATH" bash -c 'echo "$BASH_VERSION"'
  [ "$status" -eq 0 ]
  [[ "$output" == 3.* ]] || { echo "$output"; return 1; }
}

@test "the plugin CLI runs under the shim" {
  run env PATH="$SHIM:$PATH" HOME="$TEST_DIR/home" bash "$TEST_DIR/copy/bin/dotfiles-plugin" list
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "a bash-4-only construct in the plugin CLI fails under the shim" {
  # ${var,,} (lower-case expansion) is bash 4+; bash 3.2 says "bad substitution".
  printf '%s\n' '_bash32_probe=ABC; : "${_bash32_probe,,}"' >> "$TEST_DIR/copy/lib/plugin.sh"
  run env PATH="$SHIM:$PATH" HOME="$TEST_DIR/home" bash "$TEST_DIR/copy/bin/dotfiles-plugin" list
  [ "$status" -ne 0 ]
  [[ "$output" == *"bad substitution"* ]] || { echo "$output"; return 1; }
}

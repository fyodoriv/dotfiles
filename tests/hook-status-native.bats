#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_DATA_HOME="$TEST_DIR/data" TEST_ROOT="$TEST_DIR/repo"
  mkdir -p "$HOME" "$TEST_ROOT/bin" "$TEST_ROOT/lib" "$TEST_ROOT/rust/hook-status/target/release" "$TEST_DIR/mockbin"
  cp "$BATS_TEST_DIRNAME/../bin/hook-status-native" "$TEST_ROOT/bin/"
  cp "$BATS_TEST_DIRNAME/../lib/native-delivery.sh" "$TEST_ROOT/lib/"
  cat > "$TEST_ROOT/bin/heavy-run" <<'MOCK'
#!/bin/bash
[ "${FAIL_BUILD:-0}" = 0 ]
MOCK
  cat > "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status" <<'MOCK'
#!/bin/bash
exit 0
MOCK
  cat > "$TEST_DIR/mockbin/uname" <<'MOCK'
#!/bin/bash
printf '%s\n' Darwin
MOCK
  chmod +x "$TEST_ROOT/bin/heavy-run" "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status" "$TEST_DIR/mockbin/uname"
  export PATH="$TEST_DIR/mockbin:$PATH"
  INSTALLER="$TEST_ROOT/bin/hook-status-native"
  GUARD="$BATS_TEST_DIRNAME/../agent-hooks/block-dangerous-git.sh"
  DIRECTORY="$XDG_DATA_HOME/dotfiles/native/hook-status"
}

teardown() { rm -rf "$TEST_DIR"; }

probe() { printf '%s' '{"tool_input":{"command":"git status"},"cwd":"/tmp"}' | "$GUARD"; }

@test "missing helper keeps the shell guard" {
  run probe
  [ "$status" -eq 0 ]
}

@test "receiptless native execution blocks instead of allowing" {
  "$INSTALLER" install
  run probe
  [ "$status" -eq 2 ]
  [[ "$output" == *'native guard could not complete safely'* ]]
}

@test "an allow receipt and successful native process allow status" {
  printf '#!/bin/bash\nprintf A >&3\nexit 0\n' > "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status"
  "$INSTALLER" install
  run probe
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an input-reading helper can return an allow receipt" {
  printf '#!/bin/bash\ncat >/dev/null\nprintf A >&3\nexit 0\n' > "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status"
  "$INSTALLER" install
  run probe
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an allow receipt with a failed native process blocks" {
  printf '#!/bin/bash\nprintf A >&3\nexit 1\n' > "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status"
  "$INSTALLER" install
  run probe
  [ "$status" -eq 2 ]
}

@test "a fallback receipt preserves the guard exit status" {
  printf '#!/bin/bash\nprintf F >&3\nexit 7\n' > "$TEST_ROOT/rust/hook-status/target/release/dotfiles-hook-status"
  "$INSTALLER" install
  run probe
  [ "$status" -eq 7 ]
}

@test "a corrupt helper falls back to the shell guard" {
  "$INSTALLER" install
  printf 'corrupt\n' >> "$DIRECTORY/$(readlink "$DIRECTORY/current")"
  run probe
  [ "$status" -eq 0 ]
}

@test "a failed build preserves the selected helper and rollback removes it" {
  "$INSTALLER" install
  original="$(readlink "$DIRECTORY/current")"
  export FAIL_BUILD=1
  run "$INSTALLER" install
  [ "$status" -ne 0 ]
  [ "$(readlink "$DIRECTORY/current")" = "$original" ]
  "$INSTALLER" rollback
  [ ! -L "$DIRECTORY/current" ]
  run probe
  [ "$status" -eq 0 ]
}

@test "rollback refuses an unrelated link" {
  mkdir -p "$DIRECTORY"
  ln -s elsewhere "$DIRECTORY/current"
  run "$INSTALLER" rollback
  [ "$status" -ne 0 ]
  [ -L "$DIRECTORY/current" ]
}

#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" OVERRIDE_REPO="$TEST_DIR/repo"
  export OVERRIDE_CALLS="$TEST_DIR/evaluated" OVERRIDE_GREP_CALLS="$TEST_DIR/grep-calls"
  export OVERRIDE_REAL_GREP="$(command -v grep)"
  mkdir -p "$HOME" "$OVERRIDE_REPO/bin" "$OVERRIDE_REPO/modules/probe" "$TEST_DIR/bin"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$OVERRIDE_REPO/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$OVERRIDE_REPO/bin/dotfiles-doctor"
  cat > "$TEST_DIR/bin/grep" <<'SH'
#!/bin/bash
if [ "$1" = -qxF ] && [ "${!#}" = "$OVERRIDE_REPO/.overrides" ]; then
  printf 'lookup\n' >> "$OVERRIDE_GREP_CALLS"
fi
exec "$OVERRIDE_REAL_GREP" "$@"
SH
  chmod +x "$TEST_DIR/bin/grep"
  export PATH="$TEST_DIR/bin:$PATH"
  cat > "$OVERRIDE_REPO/modules/probe/doctor.sh" <<'SH'
check 'probe.exact' 'exact' 'printf "%s\n" exact >> "$OVERRIDE_CALLS"' ''
check 'probeXexact' 'literal dot' 'printf "%s\n" dot-literal >> "$OVERRIDE_CALLS"' ''
check 'probe.literal[1]' 'literal brackets' 'printf "%s\n" brackets >> "$OVERRIDE_CALLS"' ''
check 'probe.literal1' 'different brackets' 'printf "%s\n" bracket-literal >> "$OVERRIDE_CALLS"' ''
check 'probe.last' 'last line' 'printf "%s\n" last >> "$OVERRIDE_CALLS"' ''
check 'probe.spaced' 'leading whitespace' 'printf "%s\n" leading-space >> "$OVERRIDE_CALLS"' ''
SH
  printf '# comment\n\nprobe.exact\nprobe.exact\nprobe.literal[1]\n probe.spaced\nprobe.last' > "$OVERRIDE_REPO/.overrides"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "doctor snapshots literal override IDs without a grep process per check" {
  run bash "$OVERRIDE_REPO/bin/dotfiles-doctor" --module probe --quiet
  [ "$(cat "$OVERRIDE_CALLS")" = $'dot-literal\nbracket-literal\nleading-space' ]
  [ ! -e "$OVERRIDE_GREP_CALLS" ]
}

@test "a new doctor process reads edited overrides" {
  run bash "$OVERRIDE_REPO/bin/dotfiles-doctor" --module probe --quiet
  : > "$OVERRIDE_CALLS"
  printf 'probeXexact\n' > "$OVERRIDE_REPO/.overrides"
  run bash "$OVERRIDE_REPO/bin/dotfiles-doctor" --module probe --quiet
  [ "$(cat "$OVERRIDE_CALLS")" = $'exact\nbrackets\nbracket-literal\nlast\nleading-space' ]
}

@test "missing overrides still evaluate every check without lookup processes" {
  rm "$OVERRIDE_REPO/.overrides"
  run bash "$OVERRIDE_REPO/bin/dotfiles-doctor" --module probe --quiet
  [ "$(wc -l < "$OVERRIDE_CALLS" | tr -d ' ')" -eq 6 ]
  [ ! -e "$OVERRIDE_GREP_CALLS" ]
}

#!/usr/bin/env bats
# bin/headless-chrome-unlocked — counts headless Chrome runs that sit outside the heavy-run lock.

SCRIPT="$BATS_TEST_DIRNAME/../bin/headless-chrome-unlocked"

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  export PATH="$BATS_TEST_TMPDIR/stub:$PATH"
  # ps stub: prints the table in $PS_TABLE (pid ppid command).
  printf '#!/bin/bash\ncat "$PS_TABLE"\n' > "$BATS_TEST_TMPDIR/stub/ps"
  chmod +x "$BATS_TEST_TMPDIR/stub/ps"
  export PS_TABLE="$BATS_TEST_TMPDIR/ps.txt"
}

shell='/x/chrome-headless-shell --headless --remote-debugging-pipe'

@test "headless-chrome-unlocked: counts a run with no heavy-run parent" {
  cat > "$PS_TABLE" <<T
100 1 node /usr/bin/playwright test
101 100 $shell
102 100 $shell
T
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "headless-chrome-unlocked: ignores runs under a heavy-run ancestor" {
  cat > "$PS_TABLE" <<T
50 1 perl -e lock /h/heavy-run/lock /h/heavy-run/owner 15 npm run ui
100 50 node /usr/bin/playwright test
101 100 $shell
102 100 $shell
T
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "headless-chrome-unlocked: ignores Chrome child processes (--type=)" {
  cat > "$PS_TABLE" <<T
100 1 node pw
101 100 $shell
102 101 /x/chrome-headless-shell --type=renderer --headless
T
  run "$SCRIPT"
  [ "$output" = "1" ]
}

@test "headless-chrome-unlocked: counts only Chrome binaries, not wrappers or search tools" {
  cat > "$PS_TABLE" <<T
43399 1 /bin/bash /d/bin/dotfiles-quit-relay /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --remote-debugging-port=9223
43414 43399 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --remote-debugging-port=9223
500 1 rg --headless src
501 1 grep -r --headless-shell docs
T
  run "$SCRIPT"
  [ "$output" = "1" ]
}

@test "headless-chrome-unlocked: --check fails above HEADLESS_UNLOCKED_MAX" {
  cat > "$PS_TABLE" <<T
100 1 node pw
101 100 $shell
102 100 $shell
103 100 $shell
T
  HEADLESS_UNLOCKED_MAX=2 run "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"heavy-run"* ]]
  HEADLESS_UNLOCKED_MAX=3 run "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

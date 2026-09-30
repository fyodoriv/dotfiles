#!/usr/bin/env bats
# Tests for bin/chromework-open-url and bin/chromework-activate

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/Applications"

  export TEST_DIR
  export CHROME_APP_DIR="$TEST_DIR/Chrome.app"
  export CHROME_USER_DATA_DIR="$TEST_DIR/chrome-profile"
  mkdir -p "$CHROME_APP_DIR/Contents/MacOS" "$CHROME_USER_DATA_DIR"

  cat > "$CHROME_APP_DIR/Contents/MacOS/Google Chrome" <<'EOF'
#!/bin/bash
echo "chrome launched: $*" >> "$CHROME_USER_DATA_DIR/launch.log"
exit 0
EOF
  chmod +x "$CHROME_APP_DIR/Contents/MacOS/Google Chrome"

  export ACTIVATE_LOG="$TEST_DIR/activate.log"
  cat > "$TEST_DIR/chromework-activate-stub" <<'EOF'
#!/bin/bash
echo "$*" >> "$ACTIVATE_LOG"
exit 0
EOF
  chmod +x "$TEST_DIR/chromework-activate-stub"

  export OPEN_URL="$BATS_TEST_DIRNAME/../bin/chromework-open-url"
  export ACTIVATE="$BATS_TEST_DIRNAME/../bin/chromework-activate"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "chromework-open-url: exits 2 without url" {
  run "$OPEN_URL"
  [ "$status" -eq 2 ]
}

@test "chromework-open-url: exits 2 when Chrome missing" {
  export CHROME_APP_DIR="$TEST_DIR/missing.app"
  run "$OPEN_URL" "https://example.com"
  [ "$status" -eq 2 ]
}

@test "chromework-open-url: launches chrome with work profile args" {
  CHROMEWORK_ACTIVATE_HELPER="$TEST_DIR/chromework-activate-stub" \
    run "$OPEN_URL" "https://example.com"

  [ "$status" -eq 0 ]
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -f "$CHROME_USER_DATA_DIR/launch.log" ] && break
    sleep 0.05
  done
  grep -q -- '--user-data-dir='"$CHROME_USER_DATA_DIR" "$CHROME_USER_DATA_DIR/launch.log"
  grep -q 'https://example.com' "$CHROME_USER_DATA_DIR/launch.log"
  grep -q '^--now$' "$ACTIVATE_LOG"
  grep -q '^--survive-handoff$' "$ACTIVATE_LOG"
}

@test "chromework-open-url: --no-activate skips activation helpers" {
  CHROMEWORK_ACTIVATE_HELPER="$TEST_DIR/chromework-activate-stub" \
    run "$OPEN_URL" --no-activate "https://example.com"

  [ "$status" -eq 0 ]
  [ ! -s "$ACTIVATE_LOG" ]
}

@test "chromework-activate: --now retries when no chrome process yet" {
  export CHROME_USER_DATA_DIR="$TEST_DIR/retry-profile"
  mkdir -p "$CHROME_USER_DATA_DIR"

  (
    sleep 0.12
    cat > "$TEST_DIR/fake-chrome.pid" <<PIDECHO
12345 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome
PIDECHO
  ) &

  pgrep() {
    if [ "$1" = "-lf" ]; then
      [ -f "$TEST_DIR/fake-chrome.pid" ] && cat "$TEST_DIR/fake-chrome.pid"
      return 0
    fi
    command pgrep "$@"
  }
  export -f pgrep

  osascript() {
    if [ "$#" -gt 0 ]; then
      return 1
    fi
    printf '%s' "no"
  }
  export -f osascript

  run "$ACTIVATE" --now
  [ "$status" -eq 0 ]
}

@test "chromework-activate: uses AppleScript activate when Work Chrome has windows" {
  export CHROME_USER_DATA_DIR="$TEST_DIR/work-profile"
  mkdir -p "$CHROME_USER_DATA_DIR"

  osascript() {
    if [ "$#" -gt 0 ]; then
      return 1
    fi
    printf '%s' "yes"
  }
  export -f osascript

  run "$ACTIVATE" --now
  [ "$status" -eq 0 ]
}

@test "chromework-activate: finds default Work Chrome without user-data-dir in ps" {
  export CHROME_USER_DATA_DIR="$TEST_DIR/work-profile"
  mkdir -p "$CHROME_USER_DATA_DIR"

  pgrep() {
    if [ "$1" = "-lf" ] && [ "$2" = "/MacOS/Google Chrome$" ]; then
      printf '%s\n' "333 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
      return 0
    fi
    command pgrep "$@"
  }
  export -f pgrep

  osascript() {
    if [ "$#" -gt 0 ]; then
      [[ "$*" == *"unix id is 333"* ]]
      return $?
    fi
    printf '%s' "no"
  }
  export -f osascript

  run "$ACTIVATE" --now
  [ "$status" -eq 0 ]
}

@test "chromework-activate: prefers work user-data-dir over generic pgrep" {
  export CHROME_USER_DATA_DIR="$TEST_DIR/work-profile"
  mkdir -p "$CHROME_USER_DATA_DIR"

  pgrep() {
    if [ "$1" = "-lf" ]; then
      printf '%s\n' \
        "111 headless Google Chrome --user-data-dir=$TEST_DIR/agent-profile" \
        "222 work Google Chrome --user-data-dir=$CHROME_USER_DATA_DIR --profile-directory=Default"
      return 0
    fi
    command pgrep "$@"
  }
  export -f pgrep

  osascript() {
    if [ "$#" -gt 0 ]; then
      [[ "$*" == *"unix id is 222"* ]]
      return $?
    fi
    printf '%s' "no"
  }
  export -f osascript

  run "$ACTIVATE" --now
  [ "$status" -eq 0 ]
}

@test "chromework-activate: --survive-handoff retries until Chrome is frontmost" {
  export CHROME_USER_DATA_DIR="$TEST_DIR/work-profile"
  export CHROMEWORK_SURVIVE_ATTEMPTS=6
  export CHROMEWORK_SURVIVE_SLEEP=0.01
  mkdir -p "$CHROME_USER_DATA_DIR"

  export SURVIVE_CALLS="$TEST_DIR/survive-calls"
  : > "$SURVIVE_CALLS"

  osascript() {
    if [ "$#" -gt 0 ]; then
      echo check >> "$SURVIVE_CALLS"
      if [ "$(wc -l < "$SURVIVE_CALLS" | tr -d ' ')" -lt 3 ]; then
        printf '%s' "Cursor"
      else
        printf '%s' "Google Chrome"
      fi
      return 0
    fi
    printf '%s' "yes"
  }
  export -f osascript

  run "$ACTIVATE" --survive-handoff
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$SURVIVE_CALLS" | tr -d ' ')" -ge 3 ]
}

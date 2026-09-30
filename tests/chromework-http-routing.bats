#!/usr/bin/env bats
# chromework-fix-http-routing delegates to chromework-install

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/Applications/ChromeWork.app/Contents/MacOS"
  touch "$HOME/Applications/ChromeWork.app/Contents/MacOS/applet"

  TEST_BIN="$TEST_DIR/bin"
  mkdir -p "$TEST_BIN"
  cp "$BATS_TEST_DIRNAME/../bin/chromework-fix-http-routing" "$TEST_BIN/"
  chmod +x "$TEST_BIN/chromework-fix-http-routing"
  cat > "$TEST_BIN/chromework-install" <<'EOF'
#!/bin/bash
echo installed >> "$HOME/routing.log"
EOF
  chmod +x "$TEST_BIN/chromework-install"
  export PATH="$TEST_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "chromework-fix-http-routing: execs chromework-install" {
  run "$TEST_BIN/chromework-fix-http-routing"
  [ "$status" -eq 0 ]
  grep -q '^installed$' "$HOME/routing.log"
}

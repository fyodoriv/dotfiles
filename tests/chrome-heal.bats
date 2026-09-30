#!/usr/bin/env bats
# Tests for bin/chrome-heal — LaunchAgent wrapper that reasserts both
# Local State Work profile and ChromeWork as the system default browser.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/chrome-heal"

setup_stubs() {
  local is_enterprise="${1:-true}"
  STUB_BIN="$TEST_DIR/stub-bin"
  mkdir -p "$STUB_BIN" "$TEST_DIR/bin"
  export TEST_DIR

  cat > "$STUB_BIN/chezmoi" <<EOF
#!/bin/bash
case "\$*" in
  *is_enterprise*) echo "$is_enterprise" ;;
  *) echo "" ;;
esac
EOF
  chmod +x "$STUB_BIN/chezmoi"

  # Real chrome-heal resolves siblings next to itself; point SCRIPT_DIR via
  # a shim that copies chrome-heal into TEST_DIR/bin with stub siblings.
  cp "$SCRIPT" "$TEST_DIR/bin/chrome-heal"
  chmod +x "$TEST_DIR/bin/chrome-heal"

  cat > "$TEST_DIR/bin/chrome-enforce-profile" <<EOF
#!/bin/bash
echo "enforce:\$ENFORCE_RC" >> "$TEST_DIR/calls.log"
exit "\${ENFORCE_RC:-0}"
EOF
  chmod +x "$TEST_DIR/bin/chrome-enforce-profile"

  cat > "$TEST_DIR/bin/chromework-install" <<EOF
#!/bin/bash
echo "install:\$INSTALL_RC" >> "$TEST_DIR/calls.log"
exit "\${INSTALL_RC:-0}"
EOF
  chmod +x "$TEST_DIR/bin/chromework-install"

  cat > "$STUB_BIN/defaultbrowser" <<EOF
#!/bin/bash
cat "$TEST_DIR/defaultbrowser-state" 2>/dev/null || echo "* browser"
EOF
  chmod +x "$STUB_BIN/defaultbrowser"

  mkdir -p "$TEST_DIR/Chrome.app"
  export CHROME_APP_DIR="$TEST_DIR/Chrome.app"
  export PATH="$STUB_BIN:$PATH"
  export ENFORCE_RC=0
  export INSTALL_RC=0
  printf '* browser\n' > "$TEST_DIR/defaultbrowser-state"
  : > "$TEST_DIR/calls.log"
}

@test "chrome-heal: script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "chrome-heal: --help prints comment header" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Heal Chrome"
}

@test "chrome-heal: exits 2 when not enterprise" {
  setup_stubs false
  run "$TEST_DIR/bin/chrome-heal"
  [ "$status" -eq 2 ]
  [ ! -s "$TEST_DIR/calls.log" ]
}

@test "chrome-heal: runs enforce then chromework-install" {
  setup_stubs true
  run "$TEST_DIR/bin/chrome-heal"
  [ "$status" -eq 0 ]
  grep -q 'enforce:0' "$TEST_DIR/calls.log"
  grep -q 'install:0' "$TEST_DIR/calls.log"
  # Enforce must precede install
  awk '
    /enforce:/ { e=NR }
    /install:/ { i=NR }
    END { exit !(e && i && e < i) }
  ' "$TEST_DIR/calls.log"
}

@test "chrome-heal: continues when enforce skips (Chrome running)" {
  setup_stubs true
  export ENFORCE_RC=2
  run "$TEST_DIR/bin/chrome-heal"
  [ "$status" -eq 0 ]
  grep -q 'enforce:2' "$TEST_DIR/calls.log"
  grep -q 'install:0' "$TEST_DIR/calls.log"
}

@test "chrome-heal: fails when chromework-install fails" {
  setup_stubs true
  export INSTALL_RC=1
  run "$TEST_DIR/bin/chrome-heal"
  [ "$status" -eq 1 ]
  grep -q 'install:1' "$TEST_DIR/calls.log"
}

@test "chrome-heal: logs when default browser is still drifted" {
  setup_stubs true
  printf '* chrome\n' > "$TEST_DIR/defaultbrowser-state"
  run "$TEST_DIR/bin/chrome-heal"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "default browser still 'chrome'"
}

@test "chrome-heal: LaunchAgent plist invokes chrome-heal hourly" {
  local plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.chrome-profile.plist.tmpl"
  grep -q 'bin/chrome-heal' "$plist"
  grep -q '<integer>3600</integer>' "$plist"
}

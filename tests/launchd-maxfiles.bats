#!/usr/bin/env bats
# Tests for bin/dotfiles-launchd-maxfiles

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-launchd-maxfiles"

# Stub launchctl: `limit maxfiles` prints $STUB_SOFT, other calls go to a log.
_stub_tools() {
  STUB_BIN="$TEST_DIR/stub-bin"
  STUB_LOG="$TEST_DIR/calls.log"
  mkdir -p "$STUB_BIN" "$TEST_DIR/daemons"
  cat >"$STUB_BIN/launchctl" <<EOF
#!/bin/bash
echo "launchctl \$*" >>"$STUB_LOG"
if [[ "\$1 \$2" == "limit maxfiles" && \$# -eq 2 ]]; then
  printf '\tmaxfiles    %s            unlimited      \n' "\${STUB_SOFT:-256}"
fi
EOF
  cat >"$STUB_BIN/sysctl" <<EOF
#!/bin/bash
echo "\${STUB_PERPROC:-122880}"
EOF
  # Fake sudo: run the command, but turn a root-owned install into a plain copy.
  cat >"$STUB_BIN/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$STUB_LOG"
if [[ "\$1" == "install" ]]; then cp "\${@: -2:1}" "\${@: -1}"; exit 0; fi
exec "\$@"
EOF
  chmod +x "$STUB_BIN"/*
  export DOTFILES_LAUNCHCTL="$STUB_BIN/launchctl"
  export DOTFILES_SYSCTL="$STUB_BIN/sysctl"
  export DOTFILES_SUDO="$STUB_BIN/sudo"
  export DOTFILES_LAUNCHD_DAEMON_DIR="$TEST_DIR/daemons"
  unset DOTFILES_IS_AGENT
}

@test "launchd-maxfiles: script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "launchd-maxfiles: --check fails at the macOS default of 256" {
  _stub_tools
  STUB_SOFT=256 run "$SCRIPT" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"256"* ]]
  [[ "$output" == *"dotfiles-launchd-maxfiles"* ]]
}

@test "launchd-maxfiles: --check passes at 65536 and at unlimited" {
  _stub_tools
  STUB_SOFT=65536 run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  STUB_SOFT=unlimited run "$SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "launchd-maxfiles: --print-plist is a valid plist that sets soft 65536 and the kernel cap" {
  _stub_tools
  STUB_PERPROC=122880 run "$SCRIPT" --print-plist
  [ "$status" -eq 0 ]
  [[ "$output" == *"<string>com.dotfiles.maxfiles</string>"* ]]
  [[ "$output" == *"<string>65536</string>"* ]]
  [[ "$output" == *"<string>122880</string>"* ]]
  [[ "$output" == *"<key>RunAtLoad</key>"* ]]
  if command -v plutil >/dev/null 2>&1; then
    printf '%s\n' "$output" | plutil -lint - >/dev/null
  fi
}

@test "launchd-maxfiles: soft limit never exceeds a low kernel cap" {
  _stub_tools
  STUB_PERPROC=10240 run "$SCRIPT" --print-plist
  [ "$status" -eq 0 ]
  [[ "$output" != *"<string>65536</string>"* ]]
  [ "$(printf '%s\n' "$output" | grep -c '<string>10240</string>')" -eq 2 ]
}

@test "launchd-maxfiles: install refuses in an agent terminal" {
  _stub_tools
  DOTFILES_IS_AGENT=1 run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"human terminal"* ]]
  [ ! -e "$TEST_DIR/daemons/com.dotfiles.maxfiles.plist" ]
}

@test "launchd-maxfiles: install writes the daemon, bootstraps it, and applies the limit now" {
  _stub_tools
  STUB_SOFT=65536 run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/daemons/com.dotfiles.maxfiles.plist" ]
  grep -q "launchctl bootstrap system $TEST_DIR/daemons/com.dotfiles.maxfiles.plist" "$STUB_LOG"
  grep -q "launchctl limit maxfiles 65536 122880" "$STUB_LOG"
}

@test "launchd-maxfiles: --uninstall removes the daemon" {
  _stub_tools
  touch "$TEST_DIR/daemons/com.dotfiles.maxfiles.plist"
  run "$SCRIPT" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/daemons/com.dotfiles.maxfiles.plist" ]
  grep -q "launchctl bootout system/com.dotfiles.maxfiles" "$STUB_LOG"
}

@test "launchd-maxfiles: unknown flag prints usage and exits 2" {
  run "$SCRIPT" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* ]]
}

@test "resilience doctor: launchd_maxfiles warns at 256 and passes at 65536" {
  [ -x /bin/launchctl ] || skip "launchd only exists on macOS"
  _stub_tools
  mkdir -p "$DOTFILES_DIR/bin"
  cp "$SCRIPT" "$DOTFILES_DIR/bin/"
  check_cmd="$(sed -n '/resilience.launchd_maxfiles/{n;p;}' "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" | sed -E 's/^ *"(.*)" \\$/\1/; s/\\"/"/g; s/\\\$/$/g')"
  STUB_SOFT=256 run bash -c "$check_cmd"
  [ "$status" -ne 0 ]
  STUB_SOFT=65536 run bash -c "$check_cmd"
  [ "$status" -eq 0 ]
}

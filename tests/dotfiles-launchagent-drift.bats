#!/usr/bin/env bats
# bin/dotfiles-launchagent-drift (issue #297): after `dotfiles apply`, a plist
# on disk can be right while launchd still runs the old loaded copy, and a
# KeepAlive job bootstrapped from a non-GUI shell can stay not running. The
# script compares each loaded com.dotfiles.* job with its plist and, with
# --fix, reloads a drifted job and kickstarts a stopped one. A launchctl stub
# stands in for launchd; nothing real is loaded.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-launchagent-drift"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  AGENTS="$HOME/Library/LaunchAgents"
  mkdir -p "$AGENTS" "$TEST_DIR/bin" "$TEST_DIR/print"
  cat > "$TEST_DIR/bin/launchctl" <<EOF2
#!/bin/bash
echo "\$*" >> "$TEST_DIR/calls"
if [ "\$1" = print ]; then
  f="$TEST_DIR/print/\${2##*/}"
  [ -f "\$f" ] || exit 113
  cat "\$f"
fi
exit 0
EOF2
  chmod +x "$TEST_DIR/bin/launchctl"
  export PATH="$TEST_DIR/bin:$PATH"
  export DOTFILES_LAUNCHCTL="$TEST_DIR/bin/launchctl"
}

teardown() { rm -rf "$TEST_DIR"; }

# plist <label> <keepalive true|false> <arg>...
plist() {
  local label="$1" keep="$2" a args=""
  shift 2
  for a in "$@"; do args="$args<string>$a</string>"; done
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>%s</string><key>ProgramArguments</key><array>%s</array><key>RunAtLoad</key><true/><key>KeepAlive</key><%s/></dict></plist>\n' \
    "$label" "$args" "$keep" > "$AGENTS/$label.plist"
}

# loaded <label> <state> <arg>...: what `launchctl print` shows.
loaded() {
  local label="$1" state="$2" a
  shift 2
  { printf 'gui/501/%s = {\n\tstate = %s\n\targuments = {\n' "$label" "$state"
    for a in "$@"; do printf '\t\t%s\n' "$a"; done
    printf '\t}\n\tjob state = exited\n}\n'
  } > "$TEST_DIR/print/$label"
}

@test "a job whose loaded arguments match its plist and that runs is ok" {
  plist com.dotfiles.a true /bin/bash /x/a.sh
  loaded com.dotfiles.a running /bin/bash /x/a.sh
  run "$SCRIPT"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok com.dotfiles.a"* ]]
}

@test "a job whose loaded arguments differ from its plist is drift, and --fix reloads it" {
  plist com.dotfiles.chrome false /bin/bash /x/relay "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9223
  loaded com.dotfiles.chrome running "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --remote-debugging-port=9223
  run "$SCRIPT"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"drift com.dotfiles.chrome: the loaded job runs other arguments than its plist"* ]]
  run "$SCRIPT" --fix
  echo "$output"
  [ "$status" -eq 0 ]
  grep -q "^bootout gui/$(id -u)/com.dotfiles.chrome" "$TEST_DIR/calls"
  grep -q "^bootstrap gui/$(id -u) $AGENTS/com.dotfiles.chrome.plist" "$TEST_DIR/calls"
  [[ "$output" == *"reloaded com.dotfiles.chrome"* ]]
}

@test "a KeepAlive job that is not running is stopped, and --fix kickstarts it" {
  plist com.dotfiles.b true /bin/bash /x/b.sh
  loaded com.dotfiles.b "not running" /bin/bash /x/b.sh
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"stopped com.dotfiles.b: KeepAlive job is not running"* ]]
  run "$SCRIPT" --fix
  grep -q "^kickstart gui/$(id -u)/com.dotfiles.b" "$TEST_DIR/calls"
  [[ "$output" == *"kickstarted com.dotfiles.b"* ]]
}

@test "a job without KeepAlive may be not running (it ran and exited)" {
  plist com.dotfiles.c false /bin/bash /x/c.sh
  loaded com.dotfiles.c "not running" /bin/bash /x/c.sh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "a plist that is not loaded is reported, and --fix bootstraps it" {
  plist com.dotfiles.d true /bin/bash /x/d.sh
  run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unloaded com.dotfiles.d"* ]]
  run "$SCRIPT" --fix
  grep -q "^bootstrap gui/$(id -u) $AGENTS/com.dotfiles.d.plist" "$TEST_DIR/calls"
}

@test "only com.dotfiles jobs are checked" {
  plist com.other.e true /bin/bash /x/e.sh
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"com.other.e"* ]]
}

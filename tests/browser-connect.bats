#!/usr/bin/env bats

load test_helper

browser_stubs() {
  local bin_dir="$TEST_DIR/bin"
  mkdir -p "$bin_dir" "$HOME/.config/chezmoi"
  export XDG_CONFIG_HOME="$HOME/.config"
  export PROBES="$TEST_DIR/probes" ATTACHES="$TEST_DIR/attaches" READY_AT=2
  : > "$PROBES"
  : > "$ATTACHES"
  cat > "$bin_dir/curl" <<'EOF'
#!/bin/bash
[ "$1" = --disable ] || exit 9
printf '%s\n' "${!#}" >> "$PROBES"
[ "$(wc -l < "$PROBES")" -ge "$READY_AT" ]
EOF
  cat > "$bin_dir/agent-browser" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >> "$ATTACHES"
EOF
  cat > "$bin_dir/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF
  cat > "$bin_dir/git" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$bin_dir/curl" "$bin_dir/agent-browser" "$bin_dir/sleep" "$bin_dir/git"
  export PATH="$bin_dir:$BATS_TEST_DIRNAME/../bin:$PATH"
}

write_browser_settings() {
  printf 'data:\n  browser_connect_port: %s\n  browser_connect_attempts: %s\n' "$1" "$2" \
    > "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
}

@test "browser-connect retries the configured loopback port and pins one session" {
  browser_stubs
  write_browser_settings 9333 4

  run browser-connect sample-build

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1 of 4"* ]]
  [ "$(cat "$PROBES")" = $'http://127.0.0.1:9333/json/version\nhttp://127.0.0.1:9333/json/version' ]
  [ "$(cat "$ATTACHES")" = $'--session\nsample-build\n--pin-tab\nconnect\n9333' ]
}

@test "browser-connect stops after three failed default probes with no attach" {
  browser_stubs
  export READY_AT=99

  run browser-connect sample-build

  [ "$status" -eq 1 ]
  [[ "$output" == *"attempt 3 of 3"* ]]
  [ "$(sort -u "$PROBES")" = "http://127.0.0.1:9223/json/version" ]
  [ "$(wc -l < "$PROBES" | tr -d ' ')" -eq 3 ]
  [ ! -s "$ATTACHES" ]
}

@test "browser-connect rejects invalid settings and absent sessions before probing" {
  browser_stubs
  write_browser_settings 65536 3
  run browser-connect sample-build
  [ "$status" -eq 2 ]
  [[ "$output" == *"browser_connect_port"* ]]

  write_browser_settings 9223 11
  run browser-connect sample-build
  [ "$status" -eq 2 ]
  [[ "$output" == *"browser_connect_attempts"* ]]

  run browser-connect
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage: browser-connect <session>"* ]]
  [ ! -s "$PROBES" ]
  [ ! -s "$ATTACHES" ]
}

@test "browser-connect and the Dotfiles action show the same usage" {
  browser_stubs
  run browser-connect --help
  [ "$status" -eq 0 ]
  local helper_usage="$output"

  run "$BATS_TEST_DIRNAME/../bin/dotfiles" browser-connect --help
  [ "$status" -eq 0 ]
  [ "$output" = "$helper_usage" ]
  run "$BATS_TEST_DIRNAME/../bin/dotfiles" actions browser-connect --json
  [ "$status" -eq 0 ]
  [[ "$output" == *"browser-connect <session>"* ]]
  grep -Fq 'dotfiles browser-connect <session>' "$BATS_TEST_DIRNAME/../commands/dotfiles.md"
  [ ! -s "$PROBES" ]
  [ ! -s "$ATTACHES" ]
}

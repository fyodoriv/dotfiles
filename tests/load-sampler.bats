#!/usr/bin/env bats
# Functional tests for dotfiles-load-sampler — on-disk load history

load test_helper

SAMPLER_CMD="$BATS_TEST_DIRNAME/../bin/dotfiles-load-sampler"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_BIN="$TEST_DIR/mockbin"
  mkdir -p "$TEST_BIN" "$TEST_DIR/home"
  export HOME="$TEST_DIR/home"
  export DOTFILES_LOAD_SAMPLES="$TEST_DIR/load-samples.tsv"

  cat > "$TEST_BIN/sysctl" <<'MOCK'
#!/bin/bash
case "$*" in
  *vm.loadavg*) echo "{ ${MOCK_LOAD:-1.50} 2.00 3.00 }" ;;
  *hw.ncpu*) echo 10 ;;
  *kern.memorystatus_level*) echo 64 ;;
  *vm.swapusage*) echo "total = 2048.00M  used = 512.25M  free = 1535.75M  (encrypted)" ;;
esac
MOCK
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in
  *"-o pid=,"*) printf '11 1 98.0 /usr/bin/node\n12 1 40.5 /System/WindowServer\n13 1 3.0 /bin/zsh\n14 1 1.0 /bin/ls\n' ;;
  *"-o pid="*) printf '1\n2\n3\n' ;;
esac
MOCK
  chmod +x "$TEST_BIN/sysctl" "$TEST_BIN/ps"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "load-sampler script exists and is executable" {
  [ -x "$SAMPLER_CMD" ]
}

@test "load-sampler --help prints usage" {
  run "$SAMPLER_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "load-sampler appends one TSV row with load, memory, swap, and top processes" {
  run env PATH="$TEST_BIN:$PATH" "$SAMPLER_CMD"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$DOTFILES_LOAD_SAMPLES")" -eq 1 ]
  row="$(cat "$DOTFILES_LOAD_SAMPLES")"
  [ "$(printf '%s' "$row" | cut -f3)" = "1.50" ]
  [ "$(printf '%s' "$row" | cut -f6)" = "10" ]
  [ "$(printf '%s' "$row" | cut -f7)" = "64" ]
  [ "$(printf '%s' "$row" | cut -f8)" = "512" ]
  [ "$(printf '%s' "$row" | cut -f9)" = "3" ]
  [[ "$(printf '%s' "$row" | cut -f10)" == "node:98.0 WindowServer:40.5 zsh:3.0" ]]
}

@test "load-sampler records CPU busy % so blocked-thread load is not read as CPU saturation" {
  # Sum of %cpu (98 + 40.5 + 3 + 1 = 142.5) over 10 CPUs = 14%.
  run env PATH="$TEST_BIN:$PATH" "$SAMPLER_CMD"
  [ "$status" -eq 0 ]
  [ "$(cut -f11 "$DOTFILES_LOAD_SAMPLES")" = "14" ]
}

@test "load-sampler survives a long process list (no SIGPIPE under pipefail)" {
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in *"-o pid=,"*) for i in $(seq 1 20000); do echo "$i 1 1.0 /usr/bin/proc$i"; done ;; esac
MOCK
  chmod +x "$TEST_BIN/ps"
  run env PATH="$TEST_BIN:$PATH" "$SAMPLER_CMD"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$DOTFILES_LOAD_SAMPLES")" -eq 1 ]
}

@test "load-sampler keeps only the newest rows" {
  for _ in 1 2 3 4; do
    env PATH="$TEST_BIN:$PATH" DOTFILES_LOAD_SAMPLER_MAX_ROWS=2 "$SAMPLER_CMD"
  done
  [ "$(wc -l < "$DOTFILES_LOAD_SAMPLES")" -eq 2 ]
}

@test "load-sampler --report names the peak, overload rows, and gaps" {
  now=$(date +%s)
  printf '%s\tt1\t4.00\t0\t0\t10\t60\t0\t300\tnode:10\n' "$((now - 4000))" > "$DOTFILES_LOAD_SAMPLES"
  printf '%s\tt2\t25.00\t0\t0\t10\t20\t900\t900\tnode:400.0 bash:50\t87\n' "$((now - 3970))" >> "$DOTFILES_LOAD_SAMPLES"
  printf '%s\tt3\t3.00\t0\t0\t10\t60\t0\t300\tzsh:1\n' "$((now - 60))" >> "$DOTFILES_LOAD_SAMPLES"
  run "$SAMPLER_CMD" --report 24
  [ "$status" -eq 0 ]
  [[ "$output" == *"peak load1 25.00"* ]]
  [[ "$output" == *"overload rows (load1 > 20): 1"* ]]
  [[ "$output" == *"gap"*"t2"* ]]
  [[ "$output" == *"peak CPU busy 87%"* ]]
}

@test "load-sampler --report flags kernel-stall rows: high load at low CPU busy" {
  now=$(date +%s)
  printf '%s\tt1\t120.00\t0\t0\t10\t60\t0\t900\tGeForceNOW:40 WindowServer:20\t14\n' "$((now - 120))" > "$DOTFILES_LOAD_SAMPLES"
  printf '%s\tt2\t120.00\t0\t0\t10\t60\t0\t900\tnode:900\t95\n' "$((now - 90))" >> "$DOTFILES_LOAD_SAMPLES"
  run "$SAMPLER_CMD" --report 24
  [ "$status" -eq 0 ]
  [[ "$output" == *"kernel-stall rows (load1 > 80 at CPU busy < 35%): 1, last at t1 (top: GeForceNOW:40 WindowServer:20)"* ]]
}

@test "load-sampler --report says nothing about stalls when there are none" {
  printf '%s\tt1\t3.00\t0\t0\t10\t60\t0\t300\tzsh:1\t5\n' "$(date +%s)" > "$DOTFILES_LOAD_SAMPLES"
  run "$SAMPLER_CMD" --report 24
  [[ "$output" != *"kernel-stall"* ]]
}

@test "load-sampler LaunchAgent runs the sampler every 30 seconds" {
  local plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.load-sampler.plist.tmpl"
  [ -f "$plist" ]
  grep -q 'bin/dotfiles-load-sampler' "$plist"
  grep -A1 'StartInterval' "$plist" | grep -q '<integer>30</integer>'
}

@test "load-sampler keeps a process name with a space whole (#308)" {
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in
  *"-o pid=,"*) printf '21 1 156.3 /Library/Application Support/Vendor/zdpclassifier\n22 1 43.8 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome\n23 1 3.0 /bin/zsh\n' ;;
  *"-o pid="*) printf '1\n2\n' ;;
esac
MOCK
  chmod +x "$TEST_BIN/ps"
  run env PATH="$TEST_BIN:$PATH" "$SAMPLER_CMD"
  [ "$status" -eq 0 ]
  row="$(cat "$DOTFILES_LOAD_SAMPLES")"
  # A space inside a name becomes "_": the top list itself is space-separated.
  [[ "$(printf '%s' "$row" | cut -f10)" == "zdpclassifier:156.3 Google_Chrome:43.8 zsh:3.0" ]]
}

@test "load-sampler records pid, parent, and a redacted command for each top process (#358)" {
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
case "$*" in
  *"command= -p 501"*) echo "node /repo/node_modules/.bin/vitest run --token=abc123secret" ;;
  *"command= -p 502"*) echo "/System/WindowServer -daemon" ;;
  *"command= -p 503"*) echo "-zsh" ;;
  *"comm= -p 400"*) echo "/Users/x/.local/bin/claude" ;;
  *"comm= -p 1"*) echo "/sbin/launchd" ;;
  *"-o pid=,"*) printf '501 400 98.0 /usr/bin/node\n502 1 40.5 /System/WindowServer\n503 400 3.0 /bin/zsh\n504 1 1.0 /bin/ls\n' ;;
  *"-o pid="*) printf '1\n2\n3\n' ;;
esac
MOCK
  chmod +x "$TEST_BIN/ps"
  run env PATH="$TEST_BIN:$PATH" "$SAMPLER_CMD"
  [ "$status" -eq 0 ]
  owners="$(cut -f12 "$DOTFILES_LOAD_SAMPLES")"
  [[ "$owners" == *"501/400/claude/node /repo/node_modules/.bin/vitest run --token=***"* ]]
  [[ "$owners" == *"502/1/launchd//System/WindowServer -daemon"* ]]
  [[ "$owners" != *"abc123secret"* ]]
  [ "$(cut -f10 "$DOTFILES_LOAD_SAMPLES")" = "node:98.0 WindowServer:40.5 zsh:3.0" ]
}

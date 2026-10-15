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
  *"-o pid="*) printf '1\n2\n3\n' ;;
  *) printf ' 98.0 /usr/bin/node\n 40.5 /System/WindowServer\n 3.0 /bin/zsh\n 1.0 /bin/ls\n' ;;
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

@test "load-sampler survives a long process list (no SIGPIPE under pipefail)" {
  cat > "$TEST_BIN/ps" <<'MOCK'
#!/bin/bash
for i in $(seq 1 20000); do echo " 1.0 /usr/bin/proc$i"; done
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
  printf '%s\tt2\t25.00\t0\t0\t10\t20\t900\t900\tnode:400.0 bash:50\n' "$((now - 3970))" >> "$DOTFILES_LOAD_SAMPLES"
  printf '%s\tt3\t3.00\t0\t0\t10\t60\t0\t300\tzsh:1\n' "$((now - 60))" >> "$DOTFILES_LOAD_SAMPLES"
  run "$SAMPLER_CMD" --report 24
  [ "$status" -eq 0 ]
  [[ "$output" == *"peak load1 25.00"* ]]
  [[ "$output" == *"overload rows (load1 > 20): 1"* ]]
  [[ "$output" == *"gap"*"t2"* ]]
}

@test "load-sampler LaunchAgent runs the sampler every 30 seconds" {
  local plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.load-sampler.plist.tmpl"
  [ -f "$plist" ]
  grep -q 'bin/dotfiles-load-sampler' "$plist"
  grep -A1 'StartInterval' "$plist" | grep -q '<integer>30</integer>'
}

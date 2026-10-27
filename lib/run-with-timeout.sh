#!/bin/bash
# run_with_timeout <seconds> <command> [args...]
#
# Runs a command with a time limit. macOS has no GNU `timeout` by default.
# Prints the command's stdout. Returns the command's exit code, or 124 when
# the time limit is hit (the command is killed).
#
# Why: some reads block forever without an error. Example: `defaults read`
# on a sandboxed app's domain waits on the macOS "access data from other
# apps" privacy prompt, which an agent shell or LaunchAgent cannot answer.
run_with_timeout() {
  local limit="$1"
  shift
  local out pid rc ticks=0 max_ticks
  max_ticks=$((limit * 10))
  out="$(mktemp -t run-with-timeout.XXXXXX)"
  "$@" >"$out" 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$ticks" -ge "$max_ticks" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$out"
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  rc=0
  wait "$pid" || rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}

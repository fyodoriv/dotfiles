#!/bin/bash
# Bound the App Priority build and its queued heavy-run subprocesses.
app_priority_build_with_timeout() (
  local max_wait="$1" pid waited=0 grace=0
  shift
  # Job control puts the entire build in a separate process group.
  set -m
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$max_wait" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null && [ "$grace" -lt 5 ]; do
      sleep 1
      grace=$((grace + 1))
    done
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 124
  fi
  wait "$pid"
)

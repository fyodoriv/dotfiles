#!/bin/bash
# Bound the App Priority build and its queued heavy-run subprocesses.
app_priority_group_running() {
  local leader="$1" processes
  processes="$(ps -ax -o pgid= -o stat= 2>/dev/null)" || {
    kill -0 -- "-$leader" 2>/dev/null
    return
  }
  awk -v group="$leader" '$1 == group && $2 !~ /^Z/ { found = 1 } END { exit !found }' <<<"$processes"
}

app_priority_build_with_timeout() (
  local max_wait="$1" pid waited=0 grace=0 kill_wait=0 result=0
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
    result=124
    kill -- "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
  else
    wait "$pid" || result=$?
    if [ "$result" -ne 0 ]; then kill -- "-$pid" 2>/dev/null || true; fi
  fi
  if [ "$result" -ne 0 ]; then
    while app_priority_group_running "$pid" && [ "$grace" -lt 5 ]; do
      sleep 1
      grace=$((grace + 1))
    done
    if app_priority_group_running "$pid"; then
      kill -KILL -- "-$pid" 2>/dev/null || true
      while app_priority_group_running "$pid" && [ "$kill_wait" -lt 5 ]; do
        sleep 1
        kill_wait=$((kill_wait + 1))
      done
      if app_priority_group_running "$pid"; then
        echo 'App Priority: build processes remain after cleanup.' >&2
      fi
    fi
    wait "$pid" 2>/dev/null || true
  fi
  return "$result"
)

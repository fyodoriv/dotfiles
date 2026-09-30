#!/bin/bash
# launchctl helpers that must not block dotfiles apply indefinitely.
#
# launchctl kickstart waits until the job reaches a running state. When the
# Program binary is missing or the job cannot spawn, kickstart can hang forever
# — which blocked chezmoi apply via run_after_endpoint-security.sh.

if ! declare -f warn &>/dev/null; then
  warn() { echo "⚠ $1" >&2; }
fi

# First ProgramArguments entry, or :Program if ProgramArguments is absent.
launchagent_program_path() {
  local plist="$1"
  local program
  program="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:0' "$plist" 2>/dev/null || true)"
  if [ -z "$program" ]; then
    program="$(/usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null || true)"
  fi
  printf '%s' "$program"
}

# Returns 0 when kickstart completes within timeout_sec (default 15).
launchctl_kickstart_with_timeout() {
  local domain_service="$1"
  local timeout_sec="${2:-15}"
  local pid elapsed=0

  launchctl kickstart -k "$domain_service" &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_sec" ]; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      warn "[launchctl] kickstart timed out after ${timeout_sec}s for $domain_service"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$pid"
}

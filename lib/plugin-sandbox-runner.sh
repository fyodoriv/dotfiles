#!/bin/bash
# Runs one plugin doctor module or validate script in a child process
# (issue #145, step 6). lib/plugin-extensions.sh starts it with a cleaned
# environment, a timeout, and the plugin root as the working folder.
#
# Usage: plugin-sandbox-runner.sh <list|run|validate> <file>
#
# It prints one result per line, tab-separated, for the parent to record:
#   CHECK <id> <pass|fail> <description>     (doctor modules)
#   PASS|FAIL|WARN <message>                 (validate scripts, or pass/fail calls)
# Fix commands never run here: a plugin check reports, and the core decides.

mode="$1" file="$2"
_flat() { printf '%s' "$*" | tr '\t\n' '  '; }

skipped() { :; }
fixed() { :; }
notify() { :; }
# shellcheck disable=SC2034  # color names some plugin scripts expect
BLUE='' GREEN='' RED='' YELLOW='' DIM='' NC=''

# Plugin output other than result lines goes to stderr, never to the parser.
exec 3>&1 1>&2
check() { _check_real "$@" >&3; }
pass() { printf 'PASS\t%s\n' "$(_flat "$*")" >&3; }
fail() { printf 'FAIL\t%s\n' "$(_flat "$*")" >&3; }
audit_warn() { printf 'WARN\t%s\n' "$(_flat "$*")" >&3; }
_check_real() {
  local id="$1" desc="$2" test_cmd="$3"
  if [ "$mode" = list ]; then
    printf 'CHECK\t%s\tlist\t%s\n' "$(_flat "$id")" "$(_flat "$desc")"
  elif eval "$test_cmd" >/dev/null 2>&1; then
    printf 'CHECK\t%s\tpass\t%s\n' "$(_flat "$id")" "$(_flat "$desc")"
  else
    printf 'CHECK\t%s\tfail\t%s\n' "$(_flat "$id")" "$(_flat "$desc")"
  fi
}

# shellcheck source=/dev/null
source "$file"

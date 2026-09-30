#!/bin/bash
# Enforce the shell coverage floor recorded in .shell-coverage-floor.
set -euo pipefail

report="${1:-coverage/bats/coverage.json}"
floor_file="${2:-.shell-coverage-floor}"

if [ ! -f "$report" ]; then
  echo "Coverage report not found: $report" >&2
  exit 1
fi

if [ ! -f "$floor_file" ]; then
  echo "Coverage floor file not found: $floor_file" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Coverage check requires jq on PATH" >&2
  exit 1
fi

percent="$(jq -r '.percent_covered // empty' "$report")"
floor="$(sed -n '1p' "$floor_file")"

case "$percent" in
  '' | *[!0-9.]*)
    echo "Coverage report has invalid percent_covered: ${percent:-<empty>}" >&2
    exit 1
    ;;
esac

case "$floor" in
  '' | *[!0-9.]*)
    echo "Coverage floor is invalid: ${floor:-<empty>}" >&2
    exit 1
    ;;
esac

printf 'Coverage: %s%% (floor: %s%%)\n' "$percent" "$floor"

if awk -v percent="$percent" -v floor="$floor" 'BEGIN { exit (percent + 0 >= floor + 0) ? 0 : 1 }'; then
  echo "Coverage floor satisfied"
else
  echo "Coverage ${percent}% is below the ${floor}% floor" >&2
  exit 1
fi

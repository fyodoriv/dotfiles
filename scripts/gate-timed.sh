#!/bin/bash
# Run one `make check` step and append its duration to the gate timings log,
# so the monthly speed review (/tooling-checkup) and `dotfiles metrics --table`
# can see which gate step is slow and whether it is getting slower.
#
# Usage: scripts/gate-timed.sh <step> <command> [args...]
#   step  lint | lint-tasks | test | e2e | total
#
# Appends {"ts","step","seconds","status"} to
# $DOTFILES_GATE_TIMINGS_FILE (default ~/.local/state/dotfiles/gate-timings.jsonl),
# kept to the last 2000 lines. DOTFILES_GATE_TIMINGS=0 turns it off; the
# command still runs. Exits with the command's status.
set -uo pipefail

step="${1:?usage: gate-timed.sh <step> <command> [args...]}"
shift
case "$step" in lint|lint-tasks|test|e2e|total) ;; *) echo "gate-timed: unknown step $step" >&2; exit 2 ;; esac

start="$(date +%s)"
"$@"
status=$?
seconds=$(( $(date +%s) - start ))

if [ "${DOTFILES_GATE_TIMINGS:-1}" != "0" ]; then
  file="${DOTFILES_GATE_TIMINGS_FILE:-$HOME/.local/state/dotfiles/gate-timings.jsonl}"
  if mkdir -p "$(dirname "$file")" 2>/dev/null; then
    printf '{"ts":"%s","step":"%s","seconds":%d,"status":%d}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$step" "$seconds" "$status" >> "$file" 2>/dev/null
    if [ "$(wc -l < "$file" 2>/dev/null || echo 0)" -gt 2000 ]; then
      tail -n 2000 "$file" > "$file.tmp" 2>/dev/null && mv "$file.tmp" "$file" 2>/dev/null
    fi
  fi
fi
exit "$status"

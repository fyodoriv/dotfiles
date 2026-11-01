#!/bin/bash
# heavy-run-bench.sh — median heavy-run queue wait: one slot vs. N slots.
#
# Starts SESSIONS dummy runs at once (each sleeps RUN seconds) through
# bin/heavy-run in a scratch state folder, first with HEAVY_RUN_SLOTS=1 (the old
# single lock), then with SLOTS slots. Prints the median wait of each, the drop
# in percent, and how many memory pressure samples were not normal.
#
# Usage: scripts/heavy-run-bench.sh [SESSIONS] [RUN] [SLOTS] [RAMP]
#   defaults: 8 sessions, 4 s runs, the automatic slot count, 1 s ramp
#   (a real gate runs 5-10 min against the 15 s ramp; 4 s vs 1 s is harsher).

set -euo pipefail

sessions="${1:-8}"
run_s="${2:-4}"
slots="${3:-}"
ramp="${4:-1}"
root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/heavy-run-bench.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

if [ -z "$slots" ]; then
  slots=$(HOME="$scratch" HEAVY_RUN_DIR="$scratch/probe" "$root/bin/heavy-run" --status | sed -n 's/^free: 0\/\([0-9]*\) .*/\1/p')
fi

median() { sort -n | awk '{ a[NR] = $1 } END { if (NR % 2) print a[(NR + 1) / 2]; else print (a[NR / 2] + a[NR / 2 + 1]) / 2 }'; }

bad_pressure=0
# One round: start every session at once, wait, then print the median wait.
round() {
  local n="$1" d="$scratch/round-$1" i
  for i in $(seq "$sessions"); do
    HOME="$scratch" HEAVY_RUN_DIR="$d" HEAVY_RUN_SLOTS="$n" HEAVY_RUN_RAMP="$ramp" \
      "$root/bin/heavy-run" sleep "$run_s" &
  done
  while [ -n "$(jobs -rp)" ]; do
    lvl=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)
    [ "$lvl" -le 1 ] || bad_pressure=$((bad_pressure + 1))
    sleep 1
  done
  sed -n 's/.* waited=\([0-9]*\) .*/\1/p' "$d/waits.log" | median
}

one=$(round 1)
many=$(round "$slots")
drop=$(awk -v a="$one" -v b="$many" 'BEGIN { if (a > 0) printf "%d", (a - b) * 100 / a; else print 0 }')
echo "sessions=$sessions run=${run_s}s ramp=${ramp}s"
echo "median wait, 1 slot:  ${one}s"
echo "median wait, $slots slots: ${many}s"
echo "drop: ${drop}%"
echo "memory pressure samples not normal: $bad_pressure"

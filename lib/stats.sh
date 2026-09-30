#!/bin/bash
# Time-saved tracking helpers for automated dotfiles tasks.
# Sources colors.sh internally — callers get both colors and stats.
# Usage: source "$(cd "$(dirname "$0")/.." && pwd)/lib/stats.sh"

# shellcheck source=./colors.sh
if [ -z "${_COLORS_SOURCED:-}" ]; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/colors.sh"
fi

# ── Time-saved tracking ─────────────────────────────────────────
DOTFILES_STATS_FILE="${DOTFILES_STATS_FILE:-$HOME/.dotfiles-stats.jsonl}"

_task_estimate() {
  case "$1" in
    sync)             echo 3 ;;
    doctor)           echo 2 ;;
    audit)            echo 2 ;;
    cleanup)          echo 10 ;;
    git-maintain)     echo 5 ;;
    cursor-priority)  echo 0 ;;
    morning)          echo 15 ;;
    *)                echo 0 ;;
  esac
}

# log_run — Record a completed automation run for time-saved tracking.
#
# Args:
#   $1  task name. Must match one of the keys in _task_estimate (sync,
#       doctor, audit, cleanup, git-maintain, cursor-priority, morning).
#       Unknown task names are silently logged with seconds_saved=0; the
#       JSONL line is still appended so total run counts stay accurate.
#   $2  units (optional, default 1). Multiplier for the per-unit estimate.
#       Use units when one invocation actually does N units of work
#       (e.g. doctor reports 100 checks pass — pass units=100 if you
#       want to scale; existing convention is units=1 for doctor).
#
# Side effects: appends one JSONL line to $DOTFILES_STATS_FILE
# (default: ~/.dotfiles-stats.jsonl). Creates the parent directory if
# missing. Silently returns if the directory cannot be created — never
# fails the calling script. Stats is best-effort instrumentation, never
# a blocker on the caller's actual work.
#
# Returns: 0 always (failures are logged to stderr, not propagated).
#
# Example (in a bin script after the work succeeds):
#   source "$(dirname "$0")/../lib/stats.sh"
#   # ... do the work ...
#   log_run sync                # 1 run × 3s = 3s
#   log_run cleanup 5           # 5 units × 10s = 50s
log_run() {
  local task="$1" units="${2:-1}"
  local estimate
  estimate="$(_task_estimate "$task")"
  local seconds_saved=$((estimate * units))
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if ! mkdir -p "$(dirname "$DOTFILES_STATS_FILE")" 2>/dev/null; then
    echo "⚠ stats: cannot create directory for $DOTFILES_STATS_FILE" >&2
    return 0
  fi
  # Suppress write errors AND swallow the non-zero exit so a read-only
  # or full stats file never aborts the calling automation script.
  if ! echo "{\"task\":\"$task\",\"timestamp\":\"$timestamp\",\"seconds_saved\":$seconds_saved,\"units\":$units}" \
        >> "$DOTFILES_STATS_FILE" 2>/dev/null; then
    echo "⚠ stats: cannot write to $DOTFILES_STATS_FILE" >&2
    return 0
  fi
  return 0
}

# get_time_saved_summary — Print a one-line summary of total automation runs
# and time saved across the entire history file.
#
# Args: none.
#
# Side effects: none — reads $DOTFILES_STATS_FILE and writes one line to
# stdout. Does not modify the stats file.
#
# Output format:
#   "0 runs, 0m saved"            (when the file is missing or empty)
#   "<N> runs, ~<M>m saved"       (when total < 1 hour)
#   "<N> runs, ~<H>h <M>m saved"  (when total ≥ 1 hour)
#
# Returns: 0 always.
#
# Example (used by `dotfiles-stats --oneliner` and shell prompt widgets):
#   source "$(dirname "$0")/../lib/stats.sh"
#   echo "$(get_time_saved_summary)"   # → "42 runs, ~12m saved"
get_time_saved_summary() {
  if [ ! -f "$DOTFILES_STATS_FILE" ] || [ ! -s "$DOTFILES_STATS_FILE" ]; then
    echo "0 runs, 0m saved"
    return
  fi
  local total_runs total_seconds hours minutes
  total_runs=$(wc -l < "$DOTFILES_STATS_FILE" | tr -d ' ')
  total_seconds=$(jq -s '[.[].seconds_saved // 0] | add' "$DOTFILES_STATS_FILE")
  hours=$((total_seconds / 3600))
  minutes=$(( (total_seconds % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    echo "$total_runs runs, ~${hours}h ${minutes}m saved"
  else
    echo "$total_runs runs, ~${minutes}m saved"
  fi
}

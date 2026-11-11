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
    app-priority)  echo 0 ;;
    morning)          echo 15 ;;
    *)                echo 0 ;;
  esac
}

# log_run — Record a completed automation run for time-saved tracking.
#
# Args:
#   $1  task name. Must match one of the keys in _task_estimate (sync,
#       doctor, audit, cleanup, git-maintain, app-priority, morning).
#       Unknown task names are silently logged with seconds_saved=0; the
#       JSONL line is still appended so total run counts stay accurate.
#   $2  units (optional, default 1). Multiplier for the per-unit estimate.
#       Use units when one invocation actually does N units of work
#       (e.g. doctor reports 100 checks pass — pass units=100 if you
#       want to scale; existing convention is units=1 for doctor).
#   $3  outcome (optional, default ok). `error`, `fail`, `false`, or `0`
#       record "ok":false; anything else records "ok":true.
#   $4  duration in ms (optional). Default: the caller shell's $SECONDS
#       times 1000, which is the script run time when log_run runs at the end.
#   $5  failing-check count (optional). Written as "fail":N when it is a number.
#
# Side effects: appends one JSONL line to $DOTFILES_STATS_FILE (off when
# DOTFILES_STATS_LOG=0; the Makefile and tests/test_helper.bash set it)
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
# The stats log is on, except DOTFILES_STATS_LOG=0, and except inside a bats
# test unless that test sets DOTFILES_STATS_LOG=1, so no test can write the
# real ~/.dotfiles-stats.jsonl.
dotfiles_stats_log_on() {
  case "${DOTFILES_STATS_LOG:-}" in 0) return 1 ;; 1) return 0 ;; esac
  [ -z "${BATS_TEST_FILENAME:-}" ]
}

log_run() {
  dotfiles_stats_log_on || return 0
  local task="$1" units="${2:-1}" outcome="${3:-ok}" duration_ms="${4:-$((SECONDS * 1000))}" fail="${5:-}"
  # Allow-list both fields so no free text can reach the log
  # (docs/observability.md#logs): a task is a short name, units a number.
  [[ "$task" =~ ^[a-z0-9-]{1,40}$ ]] || task="invalid"
  [[ "$units" =~ ^[0-9]{1,6}$ ]] || units=1
  local ok=true
  case "$outcome" in error | fail | false | 0) ok=false ;; esac
  [[ "$duration_ms" =~ ^[0-9]{1,10}$ ]] || duration_ms=$((SECONDS * 1000))
  local fail_field=""
  [[ "$fail" =~ ^[0-9]{1,6}$ ]] && fail_field=",\"fail\":$fail"
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
  if ! echo "{\"task\":\"$task\",\"timestamp\":\"$timestamp\",\"seconds_saved\":$seconds_saved,\"units\":$units,\"ok\":$ok,\"duration_ms\":$duration_ms$fail_field}" \
        >> "$DOTFILES_STATS_FILE" 2>/dev/null; then
    echo "⚠ stats: cannot write to $DOTFILES_STATS_FILE" >&2
    return 0
  fi
  _telemetry_daily "$timestamp"
  return 0
}

# ── Command timing and telemetry hooks ──────────────────────────────────
# Both hooks below are plain bash on the common path (no new process), so a
# command pays almost nothing for them.
DOTFILES_COMMANDS_FILE="${DOTFILES_COMMANDS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/commands.jsonl}"

# Read the first line of the telemetry state file into _TELEMETRY_STATE_LINE
# ("" when there is none). bin/dotfiles-telemetry owns the file and writes it
# as one line. Shell-variable scope: it lives for this script run only.
_TELEMETRY_STATE_LINE=""
_TELEMETRY_STATE_PATH=""
_telemetry_read_state() {
  _TELEMETRY_STATE_PATH="${DOTFILES_TELEMETRY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/telemetry.json}"
  _TELEMETRY_STATE_LINE=""
  if [ -r "$_TELEMETRY_STATE_PATH" ]; then IFS= read -r _TELEMETRY_STATE_LINE <"$_TELEMETRY_STATE_PATH" 2>/dev/null || true; fi
}

# The repo root, from this file's own path, in plain bash (no new process).
_stats_repo_root() {
  _STATS_REPO_ROOT="${BASH_SOURCE[0]}"
  case "$_STATS_REPO_ROOT" in
    */*) _STATS_REPO_ROOT="${_STATS_REPO_ROOT%/*}/.." ;;
    *) _STATS_REPO_ROOT=".." ;;
  esac
}

# True for root (sudo). Plain bash. DOTFILES_TELEMETRY_TEST_UID is for tests
# only, the same seam as in bin/dotfiles-telemetry.
_stats_is_root() {
  local uid="$EUID"
  [ -z "${BATS_TEST_FILENAME:-}" ] || uid="${DOTFILES_TELEMETRY_TEST_UID:-$EUID}"
  [ "$uid" = "0" ]
}

# _telemetry_daily TIMESTAMP — after a run on a terminal, start the daily send
# as a fully detached child: its own process group, SIGHUP ignored, no open
# terminal or pipe. So it lives on when this run ends or its window closes.
# A scheduled job (no terminal) never starts it: launchd kills what a job
# leaves behind, which could stop a send half way. Those Macs send from the
# LaunchAgent com.dotfiles.telemetry instead.
# It starts nothing (and no new process) unless the stored answer is yes,
# no off switch is set (CI, DO_NOT_TRACK, DOTFILES_TELEMETRY=0), today has no
# send yet, and this clock hour has no try yet. Never as root (sudo): the
# state file would become root-owned.
# bin/dotfiles-telemetry checks every rule again; a send never fails a caller.
# Never in a test, unless DOTFILES_TELEMETRY_SPAWN=1 asks for the real path.
_telemetry_daily() {
  local tel day="${1%%T*}" hour="${1%%:*}"
  if [ -n "${BATS_TEST_FILENAME:-}" ] && [ -z "${DOTFILES_TELEMETRY_SPAWN:-}" ]; then return 0; fi
  [ -n "${DOTFILES_TELEMETRY_TTY:-}" ] || [ -n "${_DOTFILES_ON_TERMINAL:-}" ] || [ -t 0 ] || [ -t 2 ] || return 0
  ! _stats_is_root || return 0
  [ -z "${CI:-}" ] || return 0
  [ "${DOTFILES_TELEMETRY:-}" != "0" ] || return 0
  case "${DO_NOT_TRACK:-}" in "" | 0) ;; *) return 0 ;; esac
  _telemetry_read_state
  case "$_TELEMETRY_STATE_LINE" in *'"consent":"yes"'*) ;; *) return 0 ;; esac
  case "$_TELEMETRY_STATE_LINE" in *"\"last_send\":\"$day\""* | *"\"try_hour\":\"$hour\""*) return 0 ;; esac
  _stats_repo_root
  tel="$_STATS_REPO_ROOT/bin/dotfiles-telemetry"
  [ -x "$tel" ] || return 0
  (
    set -m
    trap '' HUP
    bash "$tel" daily </dev/null >/dev/null 2>&1 3>&- 8>&- 9>&- &
  ) >/dev/null 2>&1
  return 0
}

# dotfiles_telemetry_ask COMMAND [ARGS...] — before a normal `dotfiles`
# command, ask the telemetry question if it has no answer yet (the install had
# no terminal). Only where a person can answer: stdin, stdout, and stderr are
# a terminal, and CI and DO_NOT_TRACK are unset. So never in a pipe, a hook, a
# scheduler, or an agent run; there the answer stays unset and nothing is sent.
# Never before help, version, cd, completion, or machine-readable output.
# Never without a key (env or config/telemetry-key): nothing could be sent.
# After 3 unanswered questions it stays silent, and after one it stays silent
# for the rest of that day. All of this is plain bash: a run that does not
# ask starts no new process. bash 3.2 has no clock, so "dismissed today" is a
# file time: bin/dotfiles-telemetry sets the marker telemetry.asked-until to
# the next UTC midnight, and this gate compares it with "now". "Now" is the
# time of a bash here-string on descriptor 3: bash makes it and removes it
# itself, so no file is left and no process starts. The state file was written
# before now; if it looks newer, that clock is not usable and the gate goes on
# to `date`. Only then, with no marker (an older state file), or after that
# midnight does it start one `date`. Never as root (sudo).
# DOTFILES_TELEMETRY_TTY=1 is for tests only (bats has no terminal).
dotfiles_telemetry_ask() {
  local arg key_line="" marker
  case "$1" in telemetry | install | help | h | version | v | cd | actions | completion | completions | -* | __*) return 0 ;; esac
  for arg in "${@:2}"; do
    case "$arg" in --help | -h | --version | --json | --quiet | -q | --porcelain) return 0 ;; esac
  done
  if [ -z "${DOTFILES_TELEMETRY_TTY:-}" ]; then
    [ -z "${BATS_TEST_FILENAME:-}" ] || return 0
    { [ -t 0 ] && [ -t 1 ] && [ -t 2 ]; } || return 0
  fi
  ! _stats_is_root || return 0
  [ -z "${CI:-}" ] || return 0
  [ "${DOTFILES_TELEMETRY:-}" != "0" ] || return 0
  case "${DO_NOT_TRACK:-}" in "" | 0) ;; *) return 0 ;; esac
  _stats_repo_root
  if [ -z "${DOTFILES_POSTHOG_KEY:-}" ]; then
    arg="${DOTFILES_TELEMETRY_KEY_FILE:-$_STATS_REPO_ROOT/config/telemetry-key}"
    if [ -r "$arg" ]; then IFS= read -r key_line <"$arg" 2>/dev/null || true; fi
    [ -n "$key_line" ] || return 0
  fi
  _telemetry_read_state
  case "$_TELEMETRY_STATE_LINE" in *'"consent":"yes"'* | *'"consent":"no"'* | *'"asks":3'*) return 0 ;; esac
  # A question was dismissed before: it may come back once on a later day.
  case "$_TELEMETRY_STATE_LINE" in
    *'"asked_day":"2'*)
      marker="${_TELEMETRY_STATE_PATH%.json}.asked-until"
      if [ -e "$marker" ] && { [ "$marker" -nt /dev/fd/3 ] && [ ! "$_TELEMETRY_STATE_PATH" -nt /dev/fd/3 ]; } 3<<<"" 2>/dev/null; then return 0; fi
      case "$_TELEMETRY_STATE_LINE" in *"\"asked_day\":\"$(date -u +%F)\""*) return 0 ;; esac ;;
  esac
  bash "$_STATS_REPO_ROOT/bin/dotfiles-telemetry" ask --first-run || true
  return 0
}

# Keep the commands log small: over 20,000 lines, keep the newest 10,000.
# With a telemetry state file, bin/dotfiles-telemetry does the cut
# (cap-commands), because it owns the telemetry cursor: it moves the cursor
# back by the number of dropped lines, under its lock, so a line that was not
# sent yet is still sent.
# With no state file nobody answered the question: there is no cursor and
# nothing is ever sent. Then this hook cuts the log itself. It does the same
# for a state file that this user cannot read: cap-commands could not read the
# cursor and would cut nothing. So the cap also
# works where cap-commands cannot run: on a machine without jq, and for root
# (a container user). The copy (`cp -p`) keeps the owner and the mode of the
# log, so a cut by root leaves a file the user can still write.
_commands_log_cap() {
  local lines tmp
  lines="$(wc -l <"$DOTFILES_COMMANDS_FILE" 2>/dev/null)" || return 0
  lines="${lines//[^0-9]/}"
  [ "${lines:-0}" -gt 20000 ] || return 0
  if [ -r "${DOTFILES_TELEMETRY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/telemetry.json}" ]; then
    _stats_repo_root
    DOTFILES_COMMANDS_FILE="$DOTFILES_COMMANDS_FILE" bash "$_STATS_REPO_ROOT/bin/dotfiles-telemetry" cap-commands >/dev/null 2>&1 || true
    return 0
  fi
  # The newest 10,000 lines, not "from line N on": two commands that end at the
  # same moment both cut here with no lock, and the second one must not cut
  # the short log by the first one's count.
  tmp="$DOTFILES_COMMANDS_FILE.tmp.$$"
  if cp -p "$DOTFILES_COMMANDS_FILE" "$tmp" 2>/dev/null &&
    tail -n 10000 "$DOTFILES_COMMANDS_FILE" >"$tmp" 2>/dev/null &&
    mv -f "$tmp" "$DOTFILES_COMMANDS_FILE" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp" 2>/dev/null
  return 0
}

# log_command — record one `dotfiles <command>` run for performance numbers.
#
# Args:
#   $1  command name: the top-level subcommand, from the dispatch arms of
#       bin/dotfiles. Never an argument. A name that is not a short lowercase
#       word is dropped.
#   $2  outcome: `ok`, or anything else for "ok":false.
#   $3  wall time in ms.
#
# Side effects: appends one JSONL line to $DOTFILES_COMMANDS_FILE
# (~/.local/state/dotfiles/commands.jsonl), under the same on/off rule as
# log_run. The line holds the name, the time, ok, and duration_ms: no
# argument, path, or message. Returns 0 always.
log_command() {
  dotfiles_stats_log_on || return 0
  local command="$1" outcome="$2" duration_ms="$3" ok=true timestamp
  [[ "$command" =~ ^[a-z][a-z0-9-]{0,39}$ ]] || return 0
  [[ "$duration_ms" =~ ^[0-9]{1,10}$ ]] || return 0
  [ "$outcome" = "ok" ] || ok=false
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [ -d "${DOTFILES_COMMANDS_FILE%/*}" ] || mkdir -p "${DOTFILES_COMMANDS_FILE%/*}" 2>/dev/null || return 0
  echo "{\"command\":\"$command\",\"timestamp\":\"$timestamp\",\"ok\":$ok,\"duration_ms\":$duration_ms}" \
    >> "$DOTFILES_COMMANDS_FILE" 2>/dev/null || return 0
  # About one run in 200 checks the size, so the log cannot grow without end.
  if [ $((RANDOM % 200)) -eq 0 ] || [ -n "${DOTFILES_COMMANDS_ROTATE_NOW:-}" ]; then _commands_log_cap; fi
  _telemetry_daily "$timestamp"
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

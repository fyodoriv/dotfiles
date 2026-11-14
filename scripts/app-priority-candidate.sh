#!/bin/bash
# Keep core work apps interactive while backgrounding agent/model workers.
# Runs every 60s via LaunchAgent.
# Usage: app-priority

set -euo pipefail
{ [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; } && { sed -n '/^#!/d; /^$/q; /^[^#]/q; /^# shellcheck/d; s/^# \{0,1\}//p' "$0"; exit 0; }

clock_ms() {
  perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e 'printf "%.0f\n", clock_gettime(CLOCK_MONOTONIC) * 1000' 2>/dev/null
}
start_ms=$(clock_ms) || start_ms=""

# shellcheck source=../lib/stats.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/stats.sh"

# Fixture-only candidate. This file is not an installed command.
# The grouped observation can age before an action; do not deploy it.
APP_PRIORITY_BATCH_READY=0
APP_PRIORITY_BATCH_ROWS=""

find_exact_processes() {
  local requested="$1" row pid name
  if [ "$APP_PRIORITY_BATCH_READY" != 1 ]; then
    pgrep -x "$requested" 2>/dev/null || true
    return 0
  fi
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    pid="${row%% *}"
    name="${row#* }"
    [ "$name" = "$requested" ] && printf '%s\n' "$pid"
  done <<< "$APP_PRIORITY_BATCH_ROWS"
  return 0
}

prepare_default_batch() {
  local row pid name status=0
  APP_PRIORITY_BATCH_ROWS="$(pgrep -l -x 'Slack|Google Chrome|Microsoft Outlook|ghostty|WebStorm|claude|codex|ollama|bats|shellcheck|parallel' 2>/dev/null)" || status=$?
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ] || return 0
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    case "$row" in *' '*) ;; *) return 0 ;; esac
    pid="${row%% *}"
    name="${row#* }"
    case "$pid" in ''|*[!0-9]*) return 0 ;; esac
    case "$name" in
      Slack|'Google Chrome'|'Microsoft Outlook'|ghostty|WebStorm|claude|codex|ollama|bats|shellcheck|parallel) ;;
      *) return 0 ;;
    esac
  done <<< "$APP_PRIORITY_BATCH_ROWS"
  APP_PRIORITY_BATCH_READY=1
}

set_process_priority() {
  local process_name="$1"
  local process_ids
  process_ids=$(find_exact_processes "$process_name")
  [ -z "$process_ids" ] && return

  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    taskpolicy -B -t 0 -l 0 -p "$process_id" >/dev/null 2>&1 || true
  done <<< "$process_ids"
}

set_process_priority_pattern() {
  local pattern="$1"
  local process_ids
  process_ids=$(pgrep -f "$pattern" 2>/dev/null || true)
  [ -z "$process_ids" ] && return

  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    taskpolicy -B -t 0 -l 0 -p "$process_id" >/dev/null 2>&1 || true
  done <<< "$process_ids"
}

set_process_background() {
  local process_name="$1"
  local process_ids
  process_ids=$(find_exact_processes "$process_name")
  [ -z "$process_ids" ] && return

  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    taskpolicy -b -p "$process_id" >/dev/null 2>&1 || true
    renice 10 -p "$process_id" >/dev/null 2>&1 || true
  done <<< "$process_ids"
}

set_process_background_pattern() {
  local pattern="$1"
  local process_ids
  process_ids=$(pgrep -f "$pattern" 2>/dev/null || true)
  [ -z "$process_ids" ] && return

  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    taskpolicy -b -p "$process_id" >/dev/null 2>&1 || true
    renice 10 -p "$process_id" >/dev/null 2>&1 || true
  done <<< "$process_ids"
}

set_process_nice_pattern() {
  local pattern="$1"
  local process_ids
  process_ids=$(pgrep -f "$pattern" 2>/dev/null || true)
  [ -z "$process_ids" ] && return

  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    renice 10 -p "$process_id" >/dev/null 2>&1 || true
  done <<< "$process_ids"
}

is_descendant_of_interactive_app() {
  local current_pid="$1"
  local depth=0
  local parent_pid command_path

  while [[ "$current_pid" =~ ^[0-9]+$ && "$current_pid" -gt 1 && "$depth" -lt 16 ]]; do
    command_path=$(ps -p "$current_pid" -o comm= 2>/dev/null || true)
    case "$command_path" in
      *"/WebStorm.app/"*|*"/Ghostty.app/"*|*"/Terminal.app/"*|*"/iTerm.app/"*|\
      *"/WezTerm.app/"*|*"/kitty.app/"*|*"/Alacritty.app/"*|*"/Warp.app/"*|\
      *"/Claude.app/"*|*"/ChatGPT.app/"*|*"/Codex.app/"*) return 0 ;;
    esac

    parent_pid=$(ps -p "$current_pid" -o ppid= 2>/dev/null || true)
    parent_pid="${parent_pid//[[:space:]]/}"
    [[ "$parent_pid" =~ ^[0-9]+$ && "$parent_pid" -ne "$current_pid" ]] || break
    current_pid="$parent_pid"
    depth=$((depth + 1))
  done

  return 1
}

set_agent_priority() {
  local process_name="$1"
  local process_ids
  process_ids=$(find_exact_processes "$process_name")
  [ -z "$process_ids" ] && return

  local process_id
  while IFS= read -r process_id; do
    [ -z "$process_id" ] && continue
    if is_descendant_of_interactive_app "$process_id"; then
      taskpolicy -B -t 0 -l 0 -p "$process_id" >/dev/null 2>&1 || true
      renice 0 -p "$process_id" >/dev/null 2>&1 || true
    else
      taskpolicy -b -p "$process_id" >/dev/null 2>&1 || true
      renice 10 -p "$process_id" >/dev/null 2>&1 || true
    fi
  done <<< "$process_ids"
}

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/priority-apps.txt"

if [ -f "$CONFIG_FILE" ]; then
  # Read process names from config file (one per line, # comments allowed)
  while IFS= read -r line; do
    line="${line%%#*}"            # strip inline comments
    line="${line#"${line%%[! ]*}"}" # strip leading whitespace
    line="${line%"${line##*[! ]}"}" # strip trailing whitespace
    [ -z "$line" ] && continue
    if [[ "$line" == *"*"* || "$line" == *"."* ]]; then
      set_process_priority_pattern "$line"
    else
      set_process_priority "$line"
    fi
  done < "$CONFIG_FILE"
else
  # Default process list when no config file exists
  prepare_default_batch
  # Interactive apps
  set_process_priority "Slack"
  set_process_priority "Google Chrome"
  set_process_priority "Microsoft Outlook"
  # Ghostty's macOS process name is lowercase; WebStorm retains its app name.
  set_process_priority "ghostty"
  set_process_priority "WebStorm"

  # Agent/model workers must yield to interactive apps under CPU contention.
  # Claude Code and Codex launched from a terminal or desktop app are
  # interactive sessions, so keep them responsive. Background the other agent
  # workers (launchd jobs, Remote Control, headless runs).
  set_agent_priority "claude"
  set_agent_priority "codex"
  set_process_background "ollama"
  set_process_background_pattern "mlx_lm.server"
  set_process_background_pattern "node.*minsky"

  # Verification remains available but cannot starve the desktop.
  set_process_background "bats"
  set_process_background "shellcheck"
  set_process_background "parallel"
  # Test runners that agents start run as node or bash, so `pgrep -x` misses
  # them. Eleven parallel gates froze the desktop on 2026-10-15. Renice only:
  # background QoS throttled their I/O and stretched a gate to 2.5 hours.
  set_process_nice_pattern "node_modules/vitest"
  set_process_nice_pattern "node_modules/typescript/bin/tsc"
  set_process_nice_pattern "bats-core"
  set_process_nice_pattern "/biome "
fi

end_ms=$(clock_ms) || end_ms=""
if [[ "$start_ms" =~ ^[0-9]{1,12}$ && "$end_ms" =~ ^[0-9]{1,12}$ ]] && (( end_ms >= start_ms && end_ms - start_ms <= 9999999999 )); then
  log_run app-priority 1 ok "$((end_ms - start_ms))" "" monotonic-ms
else
  log_run app-priority
fi

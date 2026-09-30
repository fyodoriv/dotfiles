#!/bin/bash
# Shared process-scoped keepawake helpers for Cursor and Claude Code.
# Sourced by bin/dotfiles-agent-keepawake and resilience doctor checks.
#
# The manager owns only the child caffeinate processes and Amphetamine session
# that it records below. It never stops a user-owned Amphetamine session.

# shellcheck disable=SC2034  # reply variables are an intentional shell API
REPLY_PID=""
REPLY_AGENT_PATH=""
REPLY_IDE_PATH=""
REPLY_POWER_DESCRIPTION=""
REPLY_BATTERY_PERCENT=""
REPLY_CHILD_PID=""
REPLY_OSASCRIPT_OUTPUT=""
REPLY_AMPHETAMINE_QUARANTINE_OPERATION=""
REPLY_AMPHETAMINE_QUARANTINE_KIND=""

AGENT_KEEPAWAKE_IDE_PATHS=(
  "/Applications/Cursor.app/Contents/MacOS/Cursor"
)

dotfiles_agent_state_dir() {
  printf '%s\n' "${DOTFILES_AGENT_KEEPAWAKE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
}

dotfiles_agent_caffeinate_state_file() {
  printf '%s/agent-keepawake-caffeinate.tsv\n' "$(dotfiles_agent_state_dir)"
}

dotfiles_agent_amphetamine_owner_marker() {
  printf '%s/agent-keepawake-amphetamine-owner\n' "$(dotfiles_agent_state_dir)"
}

dotfiles_agent_amphetamine_error_file() {
  printf '%s/agent-keepawake-amphetamine-error\n' "$(dotfiles_agent_state_dir)"
}

dotfiles_agent_amphetamine_quarantine_file() {
  printf '%s/agent-keepawake-amphetamine-quarantine\n' "$(dotfiles_agent_state_dir)"
}

dotfiles_agent_manager_lock_dir() {
  printf '%s/agent-keepawake.lock\n' "$(dotfiles_agent_state_dir)"
}

dotfiles_agent_pmset_bin() {
  printf '%s\n' "${DOTFILES_AGENT_PMSET_BIN:-pmset}"
}

dotfiles_agent_ps_bin() {
  # LaunchAgents must work before Homebrew PATH setup, so use macOS ps rather
  # than the optional `procs` utility for this process-lifecycle check.
  printf '%s\n' "${DOTFILES_AGENT_PS_BIN:-/bin/ps}"
}

dotfiles_agent_caffeinate_bin() {
  printf '%s\n' "${DOTFILES_AGENT_CAFFEINATE_BIN:-/usr/bin/caffeinate}"
}

dotfiles_agent_osascript_bin() {
  printf '%s\n' "${DOTFILES_AGENT_OSASCRIPT_BIN:-osascript}"
}

dotfiles_agent_amphetamine_app_path() {
  printf '%s\n' "${AMPHETAMINE_APP_PATH:-/Applications/Amphetamine.app}"
}

dotfiles_agent_osascript_timeout_seconds() {
  local seconds="${DOTFILES_AGENT_OSASCRIPT_TIMEOUT_SECONDS:-5}"
  if [[ ! "$seconds" =~ ^[0-9]+$ ]] || (( 10#$seconds < 1 || 10#$seconds > 30 )); then
    seconds=5
  fi
  printf '%s\n' "$seconds"
}

dotfiles_agent_amphetamine_retry_seconds() {
  local seconds="${DOTFILES_AGENT_AMPHETAMINE_RETRY_SECONDS:-300}"
  if [[ ! "$seconds" =~ ^[0-9]+$ ]] || (( 10#$seconds < 1 || 10#$seconds > 86400 )); then
    seconds=300
  fi
  printf '%s\n' "$seconds"
}

dotfiles_agent_epoch_seconds() {
  local now="${DOTFILES_AGENT_KEEPAWAKE_NOW_EPOCH:-}"
  if [[ "$now" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$now"
  else
    date +%s
  fi
}

dotfiles_agent_run_osascript() {
  local script="$1" osascript_bin output_file child_pid timeout_seconds
  local elapsed status

  REPLY_OSASCRIPT_OUTPUT=""
  osascript_bin="$(dotfiles_agent_osascript_bin)"
  timeout_seconds="$(dotfiles_agent_osascript_timeout_seconds)"
  output_file="$(mktemp "${TMPDIR:-/tmp}/dotfiles-agent-keepawake-osascript.XXXXXX")" || {
    REPLY_OSASCRIPT_OUTPUT="could not create an AppleScript output file"
    return 1
  }

  "$osascript_bin" -e "$script" > "$output_file" 2>&1 &
  child_pid="$!"
  for ((elapsed = 0; elapsed < timeout_seconds; elapsed++)); do
    if ! kill -0 "$child_pid" 2>/dev/null; then
      if wait "$child_pid"; then
        status=0
      else
        status=$?
      fi
      REPLY_OSASCRIPT_OUTPUT="$(cat "$output_file")"
      rm -f "$output_file"
      return "$status"
    fi
    sleep 1
  done

  if kill -0 "$child_pid" 2>/dev/null; then
    kill "$child_pid" 2>/dev/null || true
    for elapsed in 1 2; do
      kill -0 "$child_pid" 2>/dev/null || break
      /bin/sleep 1
    done
    kill -0 "$child_pid" 2>/dev/null && kill -KILL "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    REPLY_OSASCRIPT_OUTPUT="Amphetamine AppleScript timed out after ${timeout_seconds} seconds"
  else
    if wait "$child_pid"; then
      status=0
    else
      status=$?
    fi
    REPLY_OSASCRIPT_OUTPUT="$(cat "$output_file")"
    rm -f "$output_file"
    return "$status"
  fi

  rm -f "$output_file"
  return 124
}

dotfiles_agent_emit_claude_path_chain() {
  local candidate="$1" target

  [ -x "$candidate" ] || return 0
  printf '%s\n' "$candidate"

  # Claude's native installer points its command shim at a versioned
  # executable. ps reports that resolved path, so follow the symlink too.
  while [ -L "$candidate" ]; do
    target="$(readlink "$candidate" 2>/dev/null || true)"
    [ -n "$target" ] || break
    case "$target" in
      /*) candidate="$target" ;;
      *)
        candidate="$(cd "$(dirname "$candidate")" && cd "$(dirname "$target")" && pwd)/$(basename "$target")"
        ;;
    esac
    printf '%s\n' "$candidate"
  done
}

dotfiles_agent_claude_paths() {
  local candidate path_candidate

  # This override makes the detector easy to test without changing a user's
  # installed Claude Code path. Multiple paths are colon-separated.
  if [ -n "${DOTFILES_AGENT_CLAUDE_PATHS:-}" ]; then
    printf '%s\n' "$DOTFILES_AGENT_CLAUDE_PATHS" | tr ':' '\n'
    return 0
  fi

  candidate="${DOTFILES_AGENT_CLAUDE_PATH:-$HOME/.local/bin/claude}"
  dotfiles_agent_emit_claude_path_chain "$candidate"

  # The LaunchAgent gate also accepts a PATH-installed CLI. Match that
  # location, too, so Homebrew and other supported installations are covered.
  path_candidate="$(command -v claude 2>/dev/null || true)"
  [ "$path_candidate" = "$candidate" ] || dotfiles_agent_emit_claude_path_chain "$path_candidate"
}

dotfiles_agent_tracked_paths() {
  local agent_path
  for agent_path in "${AGENT_KEEPAWAKE_IDE_PATHS[@]}"; do
    printf '%s\n' "$agent_path"
  done
  dotfiles_agent_claude_paths
}

dotfiles_agent_list_tracked_processes() {
  local process_snapshot agent_path pid command seen_pids=""

  process_snapshot="$("$(dotfiles_agent_ps_bin)" -axww -o pid=,command= 2>/dev/null || true)"
  [ -n "$process_snapshot" ] || return 0

  while IFS= read -r agent_path; do
    [ -n "$agent_path" ] || continue
    while read -r pid command; do
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      case "$command" in
        "$agent_path"|"$agent_path "*)
          case " $seen_pids " in
            *" $pid "*) continue ;;
          esac
          seen_pids="$seen_pids $pid"
          printf '%s\t%s\n' "$pid" "$agent_path"
          ;;
      esac
    done <<< "$process_snapshot"
  done < <(dotfiles_agent_tracked_paths)
}

# Compatibility API for existing callers. It now returns the first tracked
# Cursor or Claude Code process, while the manager itself handles every PID.
dotfiles_agent_find_ide_pid() {
  local pid agent_path
  REPLY_PID=""
  REPLY_AGENT_PATH=""
  REPLY_IDE_PATH=""

  while IFS=$'\t' read -r pid agent_path; do
    [ -n "$pid" ] || continue
    REPLY_PID="$pid"
    REPLY_AGENT_PATH="$agent_path"
    REPLY_IDE_PATH="$agent_path"
    return 0
  done < <(dotfiles_agent_list_tracked_processes)
  return 1
}

dotfiles_agent_has_tracked_processes() {
  dotfiles_agent_find_ide_pid
}

dotfiles_agent_on_ac_power() {
  "$(dotfiles_agent_pmset_bin)" -g batt 2>/dev/null | grep -q 'AC Power'
}

dotfiles_agent_battery_keepawake_enabled() {
  case "${DOTFILES_AGENT_KEEPAWAKE_BATTERY:-1}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

dotfiles_agent_battery_min_percent() {
  local percent="${DOTFILES_AGENT_KEEPAWAKE_BATTERY_MIN_PERCENT:-20}"
  if [[ ! "$percent" =~ ^[0-9]+$ ]] || (( 10#$percent > 100 )); then
    percent=20
  fi
  printf '%s\n' "$percent"
}

dotfiles_agent_battery_percent() {
  local line
  while IFS= read -r line; do
    if [[ "$line" =~ ([0-9]{1,3})% ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
      return 0
    fi
  done < <("$(dotfiles_agent_pmset_bin)" -g batt 2>/dev/null)
  return 1
}

dotfiles_agent_power_qualifies() {
  local minimum
  REPLY_POWER_DESCRIPTION=""
  REPLY_BATTERY_PERCENT=""

  if dotfiles_agent_on_ac_power; then
    REPLY_POWER_DESCRIPTION="AC"
    return 0
  fi

  if ! dotfiles_agent_battery_keepawake_enabled; then
    REPLY_POWER_DESCRIPTION="battery disabled by DOTFILES_AGENT_KEEPAWAKE_BATTERY"
    return 1
  fi

  REPLY_BATTERY_PERCENT="$(dotfiles_agent_battery_percent || true)"
  minimum="$(dotfiles_agent_battery_min_percent)"
  if [[ ! "$REPLY_BATTERY_PERCENT" =~ ^[0-9]+$ ]]; then
    REPLY_POWER_DESCRIPTION="battery level unavailable"
    return 1
  fi
  if (( 10#$REPLY_BATTERY_PERCENT < 10#$minimum )); then
    REPLY_POWER_DESCRIPTION="battery ${REPLY_BATTERY_PERCENT}% below ${minimum}%"
    return 1
  fi

  REPLY_POWER_DESCRIPTION="battery ${REPLY_BATTERY_PERCENT}% (threshold ${minimum}%)"
  return 0
}

dotfiles_agent_should_keepawake() {
  dotfiles_agent_has_tracked_processes || return 1
  dotfiles_agent_power_qualifies
}

dotfiles_agent_process_command() {
  local pid="$1"
  "$(dotfiles_agent_ps_bin)" -p "$pid" -ww -o command= 2>/dev/null \
    | awk 'NR == 1 { sub(/^[[:space:]]*/, ""); print; exit }'
}

dotfiles_agent_managed_caffeinate_is_live() {
  local child_pid="$1" target_pid="$2" caffeinate_bin="$3" command
  [[ "$child_pid" =~ ^[0-9]+$ && "$target_pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$child_pid" 2>/dev/null || return 1
  command="$(dotfiles_agent_process_command "$child_pid")"
  case "$command" in
    *"$caffeinate_bin"*"-ims -w $target_pid"*) return 0 ;;
    *) return 1 ;;
  esac
}

dotfiles_agent_caffeinate_running_for_pid() {
  local target_pid="$1" child_pid command caffeinate_bin
  [[ "$target_pid" =~ ^[0-9]+$ ]] || return 1
  caffeinate_bin="$(dotfiles_agent_caffeinate_bin)"
  while read -r child_pid command; do
    case "$command" in
      *"$caffeinate_bin"*"-ims -w $target_pid"*) return 0 ;;
    esac
  done < <("$(dotfiles_agent_ps_bin)" -axww -o pid=,command= 2>/dev/null || true)
  return 1
}

dotfiles_agent_start_caffeinate() {
  local target_pid="$1" caffeinate_bin
  REPLY_CHILD_PID=""
  [[ "$target_pid" =~ ^[0-9]+$ ]] || return 1
  caffeinate_bin="$(dotfiles_agent_caffeinate_bin)"
  [ -x "$caffeinate_bin" ] || {
    printf 'dotfiles-agent-keepawake: caffeinate is unavailable: %s\n' "$caffeinate_bin" >&2
    return 1
  }

  "$caffeinate_bin" -ims -w "$target_pid" </dev/null >/dev/null 2>&1 &
  REPLY_CHILD_PID="$!"
  return 0
}

dotfiles_agent_stop_managed_caffeinate() {
  local child_pid="$1" target_pid="$2" caffeinate_bin="$3"
  if ! dotfiles_agent_managed_caffeinate_is_live "$child_pid" "$target_pid" "$caffeinate_bin"; then
    return 0
  fi
  kill "$child_pid" 2>/dev/null || ! kill -0 "$child_pid" 2>/dev/null
}

dotfiles_agent_reconcile_caffeinate() {
  local state_file state_dir temporary_file child_pid target_pid caffeinate_bin
  local kept_targets=" " result=0
  local desired_pids=" $* "

  state_file="$(dotfiles_agent_caffeinate_state_file)"
  state_dir="$(dirname "$state_file")"
  if [ "$#" -eq 0 ] && [ ! -s "$state_file" ]; then
    return 0
  fi
  mkdir -p "$state_dir" 2>/dev/null || {
    printf 'dotfiles-agent-keepawake: cannot create state directory: %s\n' "$state_dir" >&2
    return 1
  }

  temporary_file="${state_file}.tmp.$$"
  : > "$temporary_file" || return 1

  if [ -f "$state_file" ]; then
    while IFS=$'\t' read -r child_pid target_pid caffeinate_bin; do
      [[ "$child_pid" =~ ^[0-9]+$ && "$target_pid" =~ ^[0-9]+$ ]] || continue
      caffeinate_bin="${caffeinate_bin:-$(dotfiles_agent_caffeinate_bin)}"

      if ! dotfiles_agent_managed_caffeinate_is_live "$child_pid" "$target_pid" "$caffeinate_bin"; then
        continue
      fi

      case "$desired_pids" in
        *" $target_pid "*)
          case "$kept_targets" in
            *" $target_pid "*)
              dotfiles_agent_stop_managed_caffeinate "$child_pid" "$target_pid" "$caffeinate_bin" || {
                printf '%s\t%s\t%s\n' "$child_pid" "$target_pid" "$caffeinate_bin" >> "$temporary_file"
                result=1
              }
              ;;
            *)
              printf '%s\t%s\t%s\n' "$child_pid" "$target_pid" "$caffeinate_bin" >> "$temporary_file"
              kept_targets="$kept_targets$target_pid "
              ;;
          esac
          ;;
        *)
          dotfiles_agent_stop_managed_caffeinate "$child_pid" "$target_pid" "$caffeinate_bin" || {
            printf '%s\t%s\t%s\n' "$child_pid" "$target_pid" "$caffeinate_bin" >> "$temporary_file"
            result=1
          }
          ;;
      esac
    done < "$state_file"
  fi

  for target_pid in "$@"; do
    [[ "$target_pid" =~ ^[0-9]+$ ]] || continue
    case "$kept_targets" in
      *" $target_pid "*) continue ;;
    esac
    if dotfiles_agent_start_caffeinate "$target_pid"; then
      caffeinate_bin="$(dotfiles_agent_caffeinate_bin)"
      printf '%s\t%s\t%s\n' "$REPLY_CHILD_PID" "$target_pid" "$caffeinate_bin" >> "$temporary_file"
      kept_targets="$kept_targets$target_pid "
    else
      result=1
    fi
  done

  if [ -s "$temporary_file" ]; then
    mv "$temporary_file" "$state_file" || {
      rm -f "$temporary_file"
      return 1
    }
  else
    rm -f "$temporary_file" "$state_file"
  fi
  return "$result"
}

dotfiles_agent_count_stale_caffeinate() {
  local state_file child_pid target_pid caffeinate_bin count=0
  state_file="$(dotfiles_agent_caffeinate_state_file)"
  [ -f "$state_file" ] || {
    printf '0'
    return 0
  }

  while IFS=$'\t' read -r child_pid target_pid caffeinate_bin; do
    [[ "$child_pid" =~ ^[0-9]+$ && "$target_pid" =~ ^[0-9]+$ ]] || continue
    caffeinate_bin="${caffeinate_bin:-$(dotfiles_agent_caffeinate_bin)}"
    if dotfiles_agent_managed_caffeinate_is_live "$child_pid" "$target_pid" "$caffeinate_bin" \
        && ! kill -0 "$target_pid" 2>/dev/null; then
      count=$((count + 1))
    fi
  done < "$state_file"
  printf '%s' "$count"
}

dotfiles_agent_managed_caffeinate_count() {
  local state_file child_pid target_pid caffeinate_bin count=0
  state_file="$(dotfiles_agent_caffeinate_state_file)"
  [ -f "$state_file" ] || {
    printf '0'
    return 0
  }

  while IFS=$'\t' read -r child_pid target_pid caffeinate_bin; do
    [[ "$child_pid" =~ ^[0-9]+$ && "$target_pid" =~ ^[0-9]+$ ]] || continue
    caffeinate_bin="${caffeinate_bin:-$(dotfiles_agent_caffeinate_bin)}"
    if dotfiles_agent_managed_caffeinate_is_live "$child_pid" "$target_pid" "$caffeinate_bin"; then
      count=$((count + 1))
    fi
  done < "$state_file"
  printf '%s' "$count"
}

dotfiles_agent_amphetamine_fingerprint() {
  local app_path info_file version
  app_path="$(dotfiles_agent_amphetamine_app_path)"
  info_file="$app_path/Contents/Info.plist"
  version=""
  if [ -r "$info_file" ]; then
    version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_file" 2>/dev/null || true)"
  fi
  [ -n "$version" ] || version="unknown"
  printf '%s|%s\n' "$app_path" "$version"
}

dotfiles_agent_record_amphetamine_error() {
  local message="$1" error_file state_dir existing
  error_file="$(dotfiles_agent_amphetamine_error_file)"
  state_dir="$(dirname "$error_file")"
  mkdir -p "$state_dir" 2>/dev/null || return 0
  existing="$(cat "$error_file" 2>/dev/null || true)"
  [ "$existing" = "$message" ] && return 0
  printf '%s\n' "$message" > "$error_file"
  printf 'dotfiles-agent-keepawake: Amphetamine automation unavailable: %s\n' "$message" >&2
}

dotfiles_agent_amphetamine_failure_kind() {
  local message="$1"
  case "$message" in
    *"understand the message"*|*"AppleEvent handler failed"*|*"event not handled"*|*"not an allowed command"*|*"-1708"*)
      printf 'protocol\n'
      ;;
    *)
      printf 'transient\n'
      ;;
  esac
}

dotfiles_agent_amphetamine_quarantine_is_active() {
  local quarantine_file fingerprint stored_fingerprint kind operation retry_at now
  REPLY_AMPHETAMINE_QUARANTINE_OPERATION=""
  REPLY_AMPHETAMINE_QUARANTINE_KIND=""
  quarantine_file="$(dotfiles_agent_amphetamine_quarantine_file)"
  [ -s "$quarantine_file" ] || return 1

  stored_fingerprint=""
  kind=""
  operation=""
  retry_at=""
  while IFS='=' read -r key value; do
    case "$key" in
      fingerprint) stored_fingerprint="$value" ;;
      kind) kind="$value" ;;
      operation) operation="$value" ;;
      retry_at) retry_at="$value" ;;
    esac
  done < "$quarantine_file"

  fingerprint="$(dotfiles_agent_amphetamine_fingerprint)"
  if [ -z "$stored_fingerprint" ] || [ "$stored_fingerprint" != "$fingerprint" ]; then
    # A new app build can restore the scripting interface. Forget only this
    # manager's stale failure and let the next run probe the new build once.
    rm -f "$quarantine_file" "$(dotfiles_agent_amphetamine_error_file)"
    return 1
  fi

  REPLY_AMPHETAMINE_QUARANTINE_OPERATION="$operation"
  REPLY_AMPHETAMINE_QUARANTINE_KIND="$kind"
  case "$kind" in
    protocol)
      return 0
      ;;
    transient)
      now="$(dotfiles_agent_epoch_seconds)"
      if [[ "$retry_at" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] \
          && (( 10#$now < 10#$retry_at )); then
        return 0
      fi
      rm -f "$quarantine_file"
      REPLY_AMPHETAMINE_QUARANTINE_OPERATION=""
      REPLY_AMPHETAMINE_QUARANTINE_KIND=""
      return 1
      ;;
    *)
      rm -f "$quarantine_file"
      REPLY_AMPHETAMINE_QUARANTINE_OPERATION=""
      REPLY_AMPHETAMINE_QUARANTINE_KIND=""
      return 1
      ;;
  esac
}

dotfiles_agent_amphetamine_operation_is_quarantined() {
  local operation="$1"
  dotfiles_agent_amphetamine_quarantine_is_active || return 1
  [ "$REPLY_AMPHETAMINE_QUARANTINE_OPERATION" = "$operation" ]
}

dotfiles_agent_record_amphetamine_failure() {
  local operation="$1" message="$2" kind="${3:-transient}"
  local quarantine_file state_dir temporary_file fingerprint retry_at now retry_seconds

  [ -n "$message" ] || message="Amphetamine AppleScript command failed without output"
  dotfiles_agent_record_amphetamine_error "$operation: $message"

  quarantine_file="$(dotfiles_agent_amphetamine_quarantine_file)"
  state_dir="$(dirname "$quarantine_file")"
  mkdir -p "$state_dir" 2>/dev/null || return 0
  fingerprint="$(dotfiles_agent_amphetamine_fingerprint)"
  if [ "$kind" = "protocol" ]; then
    retry_at=0
  else
    now="$(dotfiles_agent_epoch_seconds)"
    retry_seconds="$(dotfiles_agent_amphetamine_retry_seconds)"
    retry_at=$((10#$now + 10#$retry_seconds))
  fi

  temporary_file="${quarantine_file}.tmp.$$"
  if (
    umask 077
    {
      printf 'fingerprint=%s\n' "$fingerprint"
      printf 'kind=%s\n' "$kind"
      printf 'operation=%s\n' "$operation"
      printf 'retry_at=%s\n' "$retry_at"
    } > "$temporary_file"
  ) && mv "$temporary_file" "$quarantine_file"; then
    :
  else
    rm -f "$temporary_file"
  fi
}

dotfiles_agent_clear_amphetamine_error() {
  rm -f "$(dotfiles_agent_amphetamine_error_file)" \
    "$(dotfiles_agent_amphetamine_quarantine_file)"
}

dotfiles_agent_amphetamine_available() {
  [ -d "$(dotfiles_agent_amphetamine_app_path)" ] \
    && command -v "$(dotfiles_agent_osascript_bin)" >/dev/null 2>&1
}

# Returns 0 for an active session, 1 for no active session, and 2 when
# Automation is unavailable or denied. A denial is persisted for doctor.
dotfiles_agent_amphetamine_session_active() {
  local output
  if ! dotfiles_agent_amphetamine_available; then
    dotfiles_agent_record_amphetamine_error "Amphetamine.app or osascript is unavailable"
    return 2
  fi

  # A protocol failure must not keep showing an Amphetamine error every
  # five seconds. The app-build keyed quarantine is retried after an update.
  if dotfiles_agent_amphetamine_quarantine_is_active; then
    return 2
  fi

  if dotfiles_agent_run_osascript 'tell application id "com.if.Amphetamine" to get session is active'; then
    output="$REPLY_OSASCRIPT_OUTPUT"
  else
    output="$REPLY_OSASCRIPT_OUTPUT"
    dotfiles_agent_record_amphetamine_failure "session-state" "$output" \
      "$(dotfiles_agent_amphetamine_failure_kind "$output")"
    return 2
  fi

  case "$output" in
    true)
      dotfiles_agent_clear_amphetamine_error
      return 0
      ;;
    false)
      dotfiles_agent_clear_amphetamine_error
      return 1
      ;;
    *)
      dotfiles_agent_record_amphetamine_failure "session-state" \
        "unexpected Amphetamine response: $output" "protocol"
      return 2
      ;;
  esac
}

dotfiles_agent_amphetamine_closed_display_mode_enabled() {
  local output
  if ! dotfiles_agent_amphetamine_available; then
    dotfiles_agent_record_amphetamine_error "Amphetamine.app or osascript is unavailable"
    return 2
  fi

  if dotfiles_agent_amphetamine_quarantine_is_active; then
    return 2
  fi

  if dotfiles_agent_run_osascript 'tell application id "com.if.Amphetamine" to get closed display mode enabled'; then
    output="$REPLY_OSASCRIPT_OUTPUT"
  else
    output="$REPLY_OSASCRIPT_OUTPUT"
    dotfiles_agent_record_amphetamine_failure "closed-display-state" "$output" \
      "$(dotfiles_agent_amphetamine_failure_kind "$output")"
    return 2
  fi

  case "$output" in
    true)
      dotfiles_agent_clear_amphetamine_error
      return 0
      ;;
    false)
      dotfiles_agent_clear_amphetamine_error
      return 1
      ;;
    *)
      dotfiles_agent_record_amphetamine_failure "closed-display-state" \
        "unexpected Amphetamine response: $output" "protocol"
      return 2
      ;;
  esac
}

dotfiles_agent_amphetamine_start_session() {
  local output
  if dotfiles_agent_amphetamine_quarantine_is_active; then
    return 1
  fi

  if dotfiles_agent_run_osascript 'tell application id "com.if.Amphetamine" to start new session with options {duration:0, interval:0, displaySleepAllowed:true}'; then
    output="$REPLY_OSASCRIPT_OUTPUT"
  else
    output="$REPLY_OSASCRIPT_OUTPUT"
    dotfiles_agent_record_amphetamine_failure "start-session" "$output" \
      "$(dotfiles_agent_amphetamine_failure_kind "$output")"
    return 1
  fi

  if [ -n "$output" ]; then
    dotfiles_agent_record_amphetamine_failure "start-session" \
      "unexpected Amphetamine response: $output" "protocol"
    return 1
  fi
  dotfiles_agent_clear_amphetamine_error
}

dotfiles_agent_amphetamine_enable_closed_display_mode() {
  local output
  if dotfiles_agent_amphetamine_quarantine_is_active; then
    return 1
  fi

  if dotfiles_agent_run_osascript 'tell application id "com.if.Amphetamine" to enable closed display mode'; then
    output="$REPLY_OSASCRIPT_OUTPUT"
  else
    output="$REPLY_OSASCRIPT_OUTPUT"
    dotfiles_agent_record_amphetamine_failure "enable-closed-display" "$output" \
      "$(dotfiles_agent_amphetamine_failure_kind "$output")"
    return 1
  fi

  if [ -n "$output" ]; then
    dotfiles_agent_record_amphetamine_failure "enable-closed-display" \
      "unexpected Amphetamine response: $output" "protocol"
    return 1
  fi
  dotfiles_agent_clear_amphetamine_error
}

dotfiles_agent_amphetamine_ensure_closed_display_mode() {
  local state
  if dotfiles_agent_amphetamine_closed_display_mode_enabled; then
    return 0
  else
    state=$?
  fi
  [ "$state" -eq 1 ] || return 1

  dotfiles_agent_amphetamine_enable_closed_display_mode || return 1
  if dotfiles_agent_amphetamine_closed_display_mode_enabled; then
    return 0
  else
    state=$?
  fi

  if [ "$state" -eq 1 ]; then
    dotfiles_agent_record_amphetamine_failure "closed-display-state" \
      "Amphetamine did not enable closed-display mode" "protocol"
  fi
  return 1
}

dotfiles_agent_amphetamine_end_session() {
  local preserve_error="${1:-0}" output
  # A state-query failure may be temporary, and an owner marker means this
  # session is ours. Permit one direct cleanup attempt, but do not repeatedly
  # send an end event that Amphetamine itself rejected.
  if dotfiles_agent_amphetamine_operation_is_quarantined "end-session"; then
    return 1
  fi

  if dotfiles_agent_run_osascript 'tell application id "com.if.Amphetamine" to end session'; then
    output="$REPLY_OSASCRIPT_OUTPUT"
  else
    output="$REPLY_OSASCRIPT_OUTPUT"
    dotfiles_agent_record_amphetamine_failure "end-session" "$output" \
      "$(dotfiles_agent_amphetamine_failure_kind "$output")"
    return 1
  fi

  if [ -n "$output" ]; then
    dotfiles_agent_record_amphetamine_failure "end-session" \
      "unexpected Amphetamine response: $output" "protocol"
    return 1
  fi
  [ "$preserve_error" = "1" ] || dotfiles_agent_clear_amphetamine_error
}

dotfiles_agent_write_amphetamine_owner_marker() {
  local closed_display="${1:-enabled}" marker_file state_dir temporary_file
  case "$closed_display" in
    enabled|pending) ;;
    *) return 1 ;;
  esac
  marker_file="$(dotfiles_agent_amphetamine_owner_marker)"
  state_dir="$(dirname "$marker_file")"
  mkdir -p "$state_dir" 2>/dev/null || return 1
  temporary_file="${marker_file}.tmp.$$"
  (
    umask 077
    {
      printf 'owner=dotfiles-agent-keepawake\n'
      printf 'started_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      printf 'closed_display=%s\n' "$closed_display"
    } > "$temporary_file"
  ) && mv "$temporary_file" "$marker_file"
}

dotfiles_agent_amphetamine_owner_marker_has_closed_display() {
  local marker_file line
  marker_file="$(dotfiles_agent_amphetamine_owner_marker)"
  [ -f "$marker_file" ] || return 1
  while IFS= read -r line; do
    [ "$line" = "closed_display=enabled" ] && return 0
  done < "$marker_file"
  return 1
}

dotfiles_agent_start_amphetamine_session() {
  local state
  if dotfiles_agent_amphetamine_session_active; then
    state=0
  else
    state=$?
  fi
  case "$state" in
    0) return 0 ;; # A pre-existing user session is deliberately untouched.
    1) ;;
    *) return 1 ;;
  esac

  if ! dotfiles_agent_amphetamine_start_session; then
    return 1
  fi

  # Persist ownership before another command can fail. If closed-display
  # setup or its rollback fails, this pending marker lets a later manager pass
  # safely retry cleanup instead of mistaking our session for a user session.
  dotfiles_agent_write_amphetamine_owner_marker pending || {
    dotfiles_agent_record_amphetamine_failure "owner-marker" \
      "could not persist Amphetamine ownership marker" "transient"
    dotfiles_agent_amphetamine_end_session 1 || true
    return 1
  }

  if ! dotfiles_agent_amphetamine_ensure_closed_display_mode; then
    # Do not leave a newly-created indefinite session behind when its
    # lid-closed behavior was not verified. Keep the pending marker when
    # Amphetamine rejects cleanup so the next eligible pass still owns it.
    if dotfiles_agent_amphetamine_end_session 1; then
      rm -f "$(dotfiles_agent_amphetamine_owner_marker)"
    fi
    return 1
  fi

  if dotfiles_agent_amphetamine_session_active; then
    state=0
  else
    state=$?
  fi
  if [ "$state" -eq 0 ]; then
    dotfiles_agent_write_amphetamine_owner_marker enabled || {
      dotfiles_agent_record_amphetamine_failure "owner-marker" \
        "could not persist Amphetamine ownership marker" "transient"
      # Do not leave an untracked indefinite session behind if local state is
      # read-only or full. This session was just created by this manager.
      dotfiles_agent_amphetamine_end_session 1 || true
      return 1
    }
    return 0
  fi

  if [ "$state" -eq 1 ]; then
    rm -f "$(dotfiles_agent_amphetamine_owner_marker)"
    dotfiles_agent_record_amphetamine_failure "session-state" \
      "Amphetamine did not start a session" "protocol"
  fi
  return 1
}

dotfiles_agent_end_owned_amphetamine_session() {
  local marker_file state
  marker_file="$(dotfiles_agent_amphetamine_owner_marker)"
  [ -f "$marker_file" ] || return 0

  if [ ! -d "$(dotfiles_agent_amphetamine_app_path)" ]; then
    rm -f "$marker_file"
    return 0
  fi

  if dotfiles_agent_amphetamine_session_active; then
    state=0
  else
    state=$?
  fi
  case "$state" in
    1)
      rm -f "$marker_file"
      return 0
      ;;
    2)
      # The marker proves ownership, so try one direct cleanup even when the
      # session query is quarantined. A rejected end command quarantines itself.
      if dotfiles_agent_amphetamine_end_session; then
        rm -f "$marker_file"
        dotfiles_agent_clear_amphetamine_error
        return 0
      fi
      return 1
      ;;
  esac

  if ! dotfiles_agent_amphetamine_end_session; then
    return 1
  fi
  rm -f "$marker_file"
  dotfiles_agent_clear_amphetamine_error
}

dotfiles_agent_reconcile_amphetamine() {
  local should_protect="$1" marker_file state
  marker_file="$(dotfiles_agent_amphetamine_owner_marker)"

  if [ "$should_protect" = "1" ]; then
    if [ -f "$marker_file" ]; then
      if dotfiles_agent_amphetamine_session_active; then
        state=0
      else
        state=$?
      fi
      case "$state" in
        0)
          if dotfiles_agent_amphetamine_owner_marker_has_closed_display; then
            return 0
          fi
          # Migrate sessions created before the closed-display verification
          # marker existed. They are manager-owned, so it is safe to configure
          # or release them rather than silently leaving a lid-close gap.
          if dotfiles_agent_amphetamine_ensure_closed_display_mode \
              && dotfiles_agent_write_amphetamine_owner_marker; then
            return 0
          fi
          if dotfiles_agent_amphetamine_end_session 1; then
            rm -f "$marker_file"
          fi
          return 1
          ;;
        1) rm -f "$marker_file" ;;
        *) return 1 ;;
      esac
    fi
    dotfiles_agent_start_amphetamine_session
    return
  fi

  dotfiles_agent_end_owned_amphetamine_session
}

# A doctor uses this to distinguish a valid long-running manager session from
# a forgotten manual Single-Use session.
dotfiles_agent_amphetamine_session_is_owned() {
  [ -f "$(dotfiles_agent_amphetamine_owner_marker)" ] \
    && dotfiles_agent_amphetamine_owner_marker_has_closed_display \
    && dotfiles_agent_has_tracked_processes \
    && dotfiles_agent_power_qualifies \
    && dotfiles_agent_amphetamine_session_active \
    && dotfiles_agent_amphetamine_closed_display_mode_enabled
}

dotfiles_agent_acquire_manager_lock() {
  local state_dir lock_dir lock_pid
  state_dir="$(dotfiles_agent_state_dir)"
  lock_dir="$(dotfiles_agent_manager_lock_dir)"
  mkdir -p "$state_dir" 2>/dev/null || return 1

  if mkdir "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$$" > "$lock_dir/pid"
    DOTFILES_AGENT_KEEPAWAKE_LOCK_DIR="$lock_dir"
    return 0
  fi

  lock_pid="$(cat "$lock_dir/pid" 2>/dev/null || true)"
  if [[ "$lock_pid" =~ ^[0-9]+$ ]] && kill -0 "$lock_pid" 2>/dev/null; then
    return 1
  fi

  rm -f "$lock_dir/pid" 2>/dev/null || return 1
  rmdir "$lock_dir" 2>/dev/null || return 1
  mkdir "$lock_dir" 2>/dev/null || return 1
  printf '%s\n' "$$" > "$lock_dir/pid"
  DOTFILES_AGENT_KEEPAWAKE_LOCK_DIR="$lock_dir"
}

dotfiles_agent_release_manager_lock() {
  local lock_dir="${DOTFILES_AGENT_KEEPAWAKE_LOCK_DIR:-}"
  [ -n "$lock_dir" ] || return 0
  rm -f "$lock_dir/pid" 2>/dev/null || true
  rmdir "$lock_dir" 2>/dev/null || true
  DOTFILES_AGENT_KEEPAWAKE_LOCK_DIR=""
}

dotfiles_agent_kickstart_keepawake_agent() {
  local domain
  domain="gui/$(id -u)"
  launchctl kickstart -k "$domain/com.dotfiles.agent-keepawake" 2>/dev/null \
    || launchctl start com.dotfiles.agent-keepawake 2>/dev/null \
    || true
}

#!/bin/bash
# Shared detection/healing for stuck Cursor agent symptoms (git-upload-pack hangs,
# stale sandbox shells). Sourced by bin/dotfiles-heal-stuck-agents and doctor modules.
#
# Vision: G1 self-healing; US-05. Never steals focus or opens GUI apps.

# shellcheck disable=SC2034  # consumed by callers
HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC="${HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC:-1800}"
HEAL_STALE_SHELL_MAX_AGE_SEC="${HEAL_STALE_SHELL_MAX_AGE_SEC:-1800}"
HEAL_RUNAWAY_AGENT_MAX_CPU_PERCENT="${HEAL_RUNAWAY_AGENT_MAX_CPU_PERCENT:-90}"
HEAL_RUNAWAY_AGENT_MIN_AGE_SEC="${HEAL_RUNAWAY_AGENT_MIN_AGE_SEC:-60}"
HEAL_CURSOR_AGENT_DNS_HOST="${HEAL_CURSOR_AGENT_DNS_HOST:-agentn.us.api5.cursor.sh}"

# macOS BSD ps exposes elapsed time as etime ([[dd-]hh:]mm:ss), not etimes (seconds).
dotfiles_heal_etime_to_seconds() {
  local etime="${1// /}"
  local days=0 hours=0 mins=0 secs=0 colons rest

  [ -n "$etime" ] || return 1

  if [[ "$etime" == *-* ]]; then
    days="${etime%%-*}"
    etime="${etime#*-}"
  fi

  colons=$(grep -o ':' <<< "$etime" | wc -l | tr -d '[:space:]')
  case "$colons" in
    2)
      IFS=: read -r hours mins secs <<< "$etime"
      ;;
    1)
      IFS=: read -r mins secs <<< "$etime"
      ;;
    0)
      secs="$etime"
      ;;
    *)
      return 1
      ;;
  esac

  days=${days#0}; days=${days:-0}
  hours=${hours#0}; hours=${hours:-0}
  mins=${mins#0}; mins=${mins:-0}
  secs=${secs#0}; secs=${secs:-0}

  printf '%s' "$((10#$days * 86400 + 10#$hours * 3600 + 10#$mins * 60 + 10#$secs))"
}

dotfiles_heal_parse_ps_line() {
  # Input: one ps line "  pid etime args…". Sets REPLY_PID, REPLY_AGE, REPLY_ARGS.
  local line="$1" pid etime args
  line="${line#"${line%%[![:space:]]*}"}"
  pid="${line%% *}"
  rest="${line#"$pid"}"
  rest="${rest#"${rest%%[![:space:]]*}"}"
  etime="${rest%% *}"
  args="${rest#"$etime"}"
  args="${args#"${args%%[![:space:]]*}"}"
  REPLY_PID="$pid"
  REPLY_AGE="$(dotfiles_heal_etime_to_seconds "$etime" 2>/dev/null || true)"
  REPLY_ARGS="$args"
}

dotfiles_heal_is_mux_master() {
  local args="$1"
  [[ "$args" == *"[mux]"* ]]
}

dotfiles_heal_ghe_ssh_host() {
  if [ -n "${DOTFILES_GHE_SSH_HOST:-}" ]; then
    printf '%s' "$DOTFILES_GHE_SSH_HOST"
    return 0
  fi
  if command -v chezmoi >/dev/null 2>&1; then
    local host
    host="$(chezmoi execute-template '{{ dig "ghe_ssh_host" "" . }}' 2>/dev/null || true)"
    if [ -n "$host" ]; then
      printf '%s' "$host"
      return 0
    fi
  fi
  return 1
}

dotfiles_heal_is_hung_git_session() {
  local args="$1" age="$2" ghe_host=""
  [[ "$age" =~ ^[0-9]+$ ]] || return 1
  dotfiles_heal_is_mux_master "$args" && return 1
  [[ "$args" != *git-upload-pack* ]] || { [ "$age" -ge "$HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC" ] && return 0; }
  ghe_host="$(dotfiles_heal_ghe_ssh_host 2>/dev/null || true)"
  if [ -n "$ghe_host" ] && [[ "$args" == *"ssh"*"$ghe_host"* ]] \
    && [ "$age" -ge "$HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC" ]; then
    return 0
  fi
  return 1
}

dotfiles_heal_iter_git_ps_lines() {
  local ghe_host pattern
  ghe_host="$(dotfiles_heal_ghe_ssh_host 2>/dev/null || true)"
  pattern='git-upload-pack|\[mux\]'
  if [ -n "$ghe_host" ]; then
    pattern="${pattern}|${ghe_host}"
  fi
  ps -ax -o pid= -o etime= -o args= 2>/dev/null \
    | grep -E "$pattern" 2>/dev/null \
    || true
}

dotfiles_heal_list_hung_git_session_pids() {
  local line pid age args
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    dotfiles_heal_parse_ps_line "$line"
    pid="$REPLY_PID"
    age="$REPLY_AGE"
    args="$REPLY_ARGS"
    [ -n "$pid" ] && [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [ -n "$age" ] || continue
    dotfiles_heal_is_hung_git_session "$args" "$age" || continue
    printf '%s\n' "$pid"
  done < <(dotfiles_heal_iter_git_ps_lines)
}

dotfiles_heal_count_hung_git_sessions() {
  dotfiles_heal_list_hung_git_session_pids | wc -l | tr -d '[:space:]'
}

dotfiles_heal_in_cursor_process_tree() {
  local pid="$1" depth=0 comm ppid args
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] && [ "$depth" -lt 20 ]; do
    comm=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d '[:space:]')
    case "$comm" in
      Cursor|cursor|Cursor\ Helper*|Code\ Helper*)
        return 0
        ;;
    esac
    args=$(ps -p "$pid" -o args= 2>/dev/null || true)
    if [[ "$args" == *extension-host* || "$args" == *cursor-agent* || "$args" == *Cursor* ]]; then
      return 0
    fi
    ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')
    [ -z "$ppid" ] || [ "$ppid" = "$pid" ] || ! [[ "$ppid" =~ ^[0-9]+$ ]] && break
    pid="$ppid"
    depth=$((depth + 1))
  done
  return 1
}

dotfiles_heal_is_stale_agent_shell() {
  local args="$1" age="$2" pid="$3"
  [[ "$age" =~ ^[0-9]+$ ]] || return 1
  [ "$age" -ge "$HEAL_STALE_SHELL_MAX_AGE_SEC" ] || return 1
  dotfiles_heal_in_cursor_process_tree "$pid" || return 1
  if [[ "$args" == *[v]itest* || "$args" == *node*vitest* ]]; then
    return 0
  fi
  if [[ "$args" == *"tail -f"* || "$args" == *"tail -F"* ]]; then
    return 0
  fi
  if [[ "$args" == *watch:pr* ]]; then
    return 0
  fi
  return 1
}

dotfiles_heal_iter_stale_shell_ps_lines() {
  ps -ax -o pid= -o etime= -o args= 2>/dev/null \
    | grep -E 'vitest|tail -f|tail -F|watch:pr' 2>/dev/null \
    || true
}

dotfiles_heal_list_stale_agent_shell_pids() {
  local line pid age args
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    dotfiles_heal_parse_ps_line "$line"
    pid="$REPLY_PID"
    age="$REPLY_AGE"
    args="$REPLY_ARGS"
    [ -n "$pid" ] && [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [ -n "$age" ] || continue
    dotfiles_heal_is_stale_agent_shell "$args" "$age" "$pid" || continue
    printf '%s\n' "$pid"
  done < <(dotfiles_heal_iter_stale_shell_ps_lines)
}

dotfiles_heal_count_stale_agent_shells() {
  dotfiles_heal_list_stale_agent_shell_pids | wc -l | tr -d '[:space:]'
}

dotfiles_heal_cpu_exceeds_limit() {
  local cpu="${1%%%}" limit="$2" whole fraction
  [[ "$cpu" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  [[ "$limit" =~ ^[0-9]+$ ]] || return 1
  whole="${cpu%%.*}"
  fraction=0
  [[ "$cpu" == *.* ]] && fraction="${cpu#*.}"
  [ "$((10#$whole))" -gt "$limit" ] \
    || { [ "$((10#$whole))" -eq "$limit" ] && [ "$((10#$fraction))" -gt 0 ]; }
}

dotfiles_heal_is_runaway_agent_helper() {
  local args="$1" age="$2" cpu="$3" pid="$4"
  [[ "$age" =~ ^[0-9]+$ ]] || return 1
  [ "$age" -ge "$HEAL_RUNAWAY_AGENT_MIN_AGE_SEC" ] || return 1
  dotfiles_heal_cpu_exceeds_limit "$cpu" "$HEAL_RUNAWAY_AGENT_MAX_CPU_PERCENT" || return 1
  dotfiles_heal_in_cursor_process_tree "$pid" || return 1

  # Cursor's .cursorignore discovery can launch `rg --files --follow`. A normal
  # discovery finishes in seconds; sustained >1-core use indicates a wedged
  # filesystem crawl. Keep the matcher narrow so user searches/tests are safe.
  if [[ "$args" == *"/ripgrep/bin/rg --files "* && "$args" == *" --follow "* ]]; then
    return 0
  fi
  return 1
}

dotfiles_heal_iter_runaway_agent_helper_ps_lines() {
  # shellcheck disable=SC2009 # Need PID + CPU + elapsed + full argv in one snapshot.
  ps -ax -o pid= -o %cpu= -o etime= -o args= 2>/dev/null \
    | grep -E '/ripgrep/bin/rg --files .* --follow( |$)' 2>/dev/null \
    || true
}

dotfiles_heal_list_runaway_agent_helper_pids() {
  local line pid cpu etime age args rest
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    line="${line#"${line%%[![:space:]]*}"}"
    pid="${line%% *}"
    rest="${line#"$pid"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    cpu="${rest%% *}"
    rest="${rest#"$cpu"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    etime="${rest%% *}"
    args="${rest#"$etime"}"
    args="${args#"${args%%[![:space:]]*}"}"
    age="$(dotfiles_heal_etime_to_seconds "$etime" 2>/dev/null || true)"
    [ -n "$pid" ] && [[ "$pid" =~ ^[0-9]+$ ]] || continue
    dotfiles_heal_is_runaway_agent_helper "$args" "$age" "$cpu" "$pid" || continue
    printf '%s\n' "$pid"
  done < <(dotfiles_heal_iter_runaway_agent_helper_ps_lines)
}

dotfiles_heal_count_runaway_agent_helpers() {
  dotfiles_heal_list_runaway_agent_helper_pids | wc -l | tr -d '[:space:]'
}

dotfiles_heal_ssh_mux_socket() {
  local host
  host="$(dotfiles_heal_ghe_ssh_host 2>/dev/null || true)"
  [ -n "$host" ] || return 1
  printf '%s/.ssh/sockets/git@%s-22\n' "${HOME:?}" "$host"
}

dotfiles_heal_reset_ssh_mux_if_idle() {
  local sock host
  sock="$(dotfiles_heal_ssh_mux_socket 2>/dev/null || true)"
  [ -n "$sock" ] && [ -S "$sock" ] || return 0
  host="$(dotfiles_heal_ghe_ssh_host)"
  # ssh -O check exits 0 when the master has active sessions.
  if ssh -O check -S "$sock" "git@$host" 2>/dev/null; then
    return 0
  fi
  ssh -O exit -S "$sock" "git@$host" 2>/dev/null || rm -f "$sock"
}

dotfiles_heal_kickstart_network_resilience() {
  local domain="gui/$(id -u)"
  launchctl kickstart -k "$domain/com.dotfiles.network-resilience" 2>/dev/null \
    || launchctl start com.dotfiles.network-resilience 2>/dev/null \
    || true
}

dotfiles_heal_cursor_agent_dns_ok() {
  host -W 2 "$HEAL_CURSOR_AGENT_DNS_HOST" >/dev/null 2>&1
}

dotfiles_heal_flush_dns_cache() {
  sudo -n dscacheutil -flushcache 2>/dev/null || true
  sudo -n killall -HUP mDNSResponder 2>/dev/null || true
}

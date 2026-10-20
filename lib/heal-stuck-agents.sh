#!/bin/bash
# Shared detection/healing for stuck agent git sessions (git-upload-pack hangs,
# idle SSH mux sockets). Sourced by bin/dotfiles-heal-stuck-agents and doctor modules.
#
# Vision: G1 self-healing; US-05. Never steals focus or opens GUI apps.

# shellcheck disable=SC2034  # consumed by callers
HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC="${HEAL_GIT_UPLOAD_PACK_MAX_AGE_SEC:-1800}"

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
  local domain
  domain="gui/$(id -u)"
  launchctl kickstart -k "$domain/com.dotfiles.network-resilience" 2>/dev/null \
    || launchctl start com.dotfiles.network-resilience 2>/dev/null \
    || true
}

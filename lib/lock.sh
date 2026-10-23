#!/bin/bash
# Shared lock helpers for preventing concurrent dotfiles operations.
# Usage: source "$(cd "$(dirname "$0")/.." && pwd)/lib/lock.sh"
#
# acquire_lock "caller-name"  →  returns 0 if acquired, 1 if locked by another
# release_lock                →  removes the lock file
#
# Lock includes PID for stale-lock detection. If the PID is dead, the lock
# is considered stale and automatically stolen. A live PID also loses the lock
# when the lock is older than DOTFILES_LOCK_MAX_AGE seconds (default 6 hours)
# and the PID's command is not a dotfiles process: the OS reused the PID.

# Ensure warn() is available — callers usually source colors.sh first, but
# scripts that source lock.sh directly need a fallback.
if ! declare -f warn &>/dev/null; then
  warn() { echo -e "⚠ $1" >&2; }
fi

DOTFILES_LOCK="${DOTFILES_LOCK:-$HOME/.dotfiles.lock}"

# Seconds after which a live-PID lock needs proof the owner is a dotfiles process.
_lock_max_age() { echo "${DOTFILES_LOCK_MAX_AGE:-21600}"; }

# Prints the lock file age in seconds (0 when unknown).
_lock_age() {
  local mtime now
  mtime=$(stat -f %m "$DOTFILES_LOCK" 2>/dev/null || stat -c %Y "$DOTFILES_LOCK" 2>/dev/null || echo "")
  [ -n "$mtime" ] || { echo 0; return; }
  now=$(date +%s)
  echo $((now - mtime))
}

# Returns 0 when the lock owner is a live PID that is still a dotfiles process,
# or a young lock whose owner is alive. Returns 1 when the owner is gone or the
# PID was reused by an unrelated process (old lock, non-dotfiles command).
_lock_owner_alive() {
  local pid="$1" cmd
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null || return 1
  [ "$(_lock_age)" -ge "$(_lock_max_age)" ] || return 0
  cmd=$(ps -o command= -p "$pid" 2>/dev/null || true)
  # No command readable: keep the lock. Never steal from a process we cannot identify.
  [ -n "$cmd" ] || return 0
  case "$cmd" in
    *dotfiles*) return 0 ;;
  esac
  return 1
}

acquire_lock() {
  local caller="${1:-unknown}"
  local lock_parent
  lock_parent=$(dirname "$DOTFILES_LOCK")

  while true; do
    # Write the PID to a private temp file, then hard-link it into place.
    # `ln` fails if the lock exists, so exactly one caller wins, and the lock
    # file never exists without its PID (no empty-file window to misread).
    local tmp_lock="$DOTFILES_LOCK.$$.tmp"
    # A folder at the lock path is never the lock: `ln` would put the link
    # inside it and succeed. Checked before and after the link (a folder can
    # appear in between); a link made inside a folder is removed again.
    if [ -d "$DOTFILES_LOCK" ]; then
      warn "[lock] Cannot acquire — $DOTFILES_LOCK is a directory — fix: rmdir \"$DOTFILES_LOCK\" (it should be a file)"
      return 1
    fi
    if printf '%s\n%s\n' "$$" "$caller" > "$tmp_lock" 2>/dev/null &&
      ln "$tmp_lock" "$DOTFILES_LOCK" 2>/dev/null; then
      if [ -d "$DOTFILES_LOCK" ]; then
        rm -f "$DOTFILES_LOCK/${tmp_lock##*/}" "$tmp_lock"
        warn "[lock] Cannot acquire — $DOTFILES_LOCK is a directory — fix: rmdir \"$DOTFILES_LOCK\" (it should be a file)"
        return 1
      fi
      rm -f "$tmp_lock"
      # shellcheck disable=SC2064 # expand $DOTFILES_LOCK at registration so cleanup still works after the variable is unset
      trap "rm -f '$DOTFILES_LOCK'" EXIT
      return 0
    fi
    rm -f "$tmp_lock"

    if [ ! -e "$DOTFILES_LOCK" ]; then
      if [ -d "$lock_parent" ]; then
        continue
      fi
      warn "[lock] Cannot create lock at $DOTFILES_LOCK — fix: mkdir -p \"$lock_parent\" and check it is writable"
      return 1
    fi

    if [ -d "$DOTFILES_LOCK" ]; then
      warn "[lock] Cannot acquire — $DOTFILES_LOCK is a directory — fix: rmdir \"$DOTFILES_LOCK\" (it should be a file)"
      return 1
    fi

    local lock_pid lock_caller tries=0 fresh_empty
    lock_pid=$(head -1 "$DOTFILES_LOCK" 2>/dev/null || echo "")
    # An empty, fresh file is a write in progress (older dotfiles versions
    # created the file before writing its PID), not a stale lock: wait briefly for the PID, and
    # if it never comes while the file is young, treat the lock as held.
    # Judge freshness once, before waiting: mtime has one-second resolution,
    # so re-checking the age inside the wait could flip a held lock to stale.
    [ -z "$lock_pid" ] && [ "$(_lock_age)" -lt 10 ] && fresh_empty=1 || fresh_empty=0
    while [ "$fresh_empty" = 1 ] && [ -z "$lock_pid" ] && [ -e "$DOTFILES_LOCK" ]; do
      if [ "$tries" -ge 10 ]; then
        [ "${_LOCK_QUIET:-0}" = 1 ] ||
          warn "[lock] Skipping — another dotfiles command is taking the lock — fix: wait for it to finish, then run again"
        return 1
      fi
      sleep 0.1
      tries=$((tries + 1))
      lock_pid=$(head -1 "$DOTFILES_LOCK" 2>/dev/null || echo "")
    done
    lock_caller=$(sed -n '2p' "$DOTFILES_LOCK" 2>/dev/null || echo "unknown")
    lock_caller="${lock_caller:-unknown}"

    # Check if the locking process is still alive
    if _lock_owner_alive "$lock_pid"; then
      [ "${_LOCK_QUIET:-0}" = 1 ] ||
        warn "[lock] Skipping — locked by $lock_caller (pid $lock_pid) — fix: wait for it to finish, then run again"
      return 1
    fi
    # Stale lock — process is dead, or its PID was reused by another program
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      warn "[lock] Removing stale lock from $lock_caller (pid $lock_pid is not a dotfiles process)"
    else
      warn "[lock] Removing stale lock from $lock_caller (pid $lock_pid)"
    fi
    if rm -f "$DOTFILES_LOCK" 2>/dev/null; then
      continue
    fi

    warn "[lock] Cannot remove stale lock at $DOTFILES_LOCK — fix: rm -f \"$DOTFILES_LOCK\" (check its owner and permissions)"
    return 1
  done
}

# lock_inherited: succeeds when DOTFILES_LOCK_HOLDER names the live process
# that holds the lock. A dotfiles command that holds the lock sets it for a
# child dotfiles command (dotfiles upgrade runs `dotfiles plugin update`),
# which then runs under the parent's lock instead of waiting on it.
lock_inherited() {
  local pid
  [ -n "${DOTFILES_LOCK_HOLDER:-}" ] || return 1
  pid="$(head -1 "$DOTFILES_LOCK" 2>/dev/null)" || return 1
  [ "$pid" = "$DOTFILES_LOCK_HOLDER" ] && kill -0 "$pid" 2>/dev/null
}

release_lock() {
  # Not used in normal operation — locks are auto-released via the EXIT trap
  # set in acquire_lock(). Kept for manual emergency cleanup in interactive shells:
  #   source lib/lock.sh && release_lock
  rm -f "$DOTFILES_LOCK"
}

# Wait for the dotfiles lock, stealing stale locks like acquire_lock().
# Used by `dotfiles apply` so chezmoi does not race concurrent doctor/sync runs.
# It says once that it waits and for whom, then at most one update every
# DOTFILES_LOCK_NOTE_EVERY seconds (default 30), and one line when it gives
# up. acquire_lock's per-try "Skipping" lines stay quiet meanwhile.
wait_for_lock() {
  local caller="${1:-unknown}"
  local max_wait="${2:-120}"
  local every="${DOTFILES_LOCK_NOTE_EVERY:-30}"
  local waited=0 noted=-1 lock_pid lock_caller
  local _LOCK_QUIET=1
  case "$max_wait" in '' | *[!0-9]*) max_wait=120 ;; esac
  case "$every" in '' | *[!0-9]* | 0) every=30 ;; esac

  while ! acquire_lock "$caller"; do
    # No lock file after a failed try means it cannot be made (no folder,
    # no write access, a folder in its place); acquire_lock said why.
    [ -f "$DOTFILES_LOCK" ] || return 1
    lock_pid=$(head -1 "$DOTFILES_LOCK" 2>/dev/null || echo "?")
    lock_caller=$(sed -n '2p' "$DOTFILES_LOCK" 2>/dev/null || echo "unknown")
    if [ "$waited" -ge "$max_wait" ]; then
      warn "[lock] Timed out after ${max_wait}s — still locked by ${lock_caller:-unknown} (pid ${lock_pid:-?})"
      return 1
    fi
    if [ "$noted" -lt 0 ]; then
      warn "[lock] Waiting for the lock held by ${lock_caller:-unknown} (pid ${lock_pid:-?}), up to ${max_wait}s"
      noted=0
    elif [ $((waited - noted)) -ge "$every" ]; then
      warn "[lock] Still waiting for ${lock_caller:-unknown} (pid ${lock_pid:-?}) after ${waited}s"
      noted=$waited
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 0
}

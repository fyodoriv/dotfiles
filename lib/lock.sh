#!/bin/bash
# Shared lock helpers for preventing concurrent dotfiles operations.
# Usage: source "$(cd "$(dirname "$0")/.." && pwd)/lib/lock.sh"
#
# acquire_lock "caller-name"  →  returns 0 if acquired, 1 if locked by another
# release_lock                →  removes the lock file
#
# Lock includes PID for stale-lock detection. If the PID is dead, the lock
# is considered stale and automatically stolen.

# Ensure warn() is available — callers usually source colors.sh first, but
# scripts that source lock.sh directly need a fallback.
if ! declare -f warn &>/dev/null; then
  warn() { echo -e "⚠ $1" >&2; }
fi

DOTFILES_LOCK="${DOTFILES_LOCK:-$HOME/.dotfiles.lock}"

acquire_lock() {
  local caller="${1:-unknown}"
  local lock_parent
  lock_parent=$(dirname "$DOTFILES_LOCK")

  while true; do
    # noclobber turns the lock write into an atomic create instead of a
    # check-then-write race between concurrent dotfiles commands.
    if (
      set -o noclobber
      printf '%s\n%s\n' "$$" "$caller" > "$DOTFILES_LOCK"
    ) 2>/dev/null; then
      # shellcheck disable=SC2064 # expand $DOTFILES_LOCK at registration so cleanup still works after the variable is unset
      trap "rm -f '$DOTFILES_LOCK'" EXIT
      return 0
    fi

    if [ ! -e "$DOTFILES_LOCK" ]; then
      if [ -d "$lock_parent" ]; then
        continue
      fi
      warn "[lock] Cannot create lock at $DOTFILES_LOCK"
      return 1
    fi

    if [ -d "$DOTFILES_LOCK" ]; then
      warn "[lock] Cannot acquire — $DOTFILES_LOCK is a directory"
      return 1
    fi

    local lock_pid lock_caller
    lock_pid=$(head -1 "$DOTFILES_LOCK" 2>/dev/null || echo "")
    lock_caller=$(sed -n '2p' "$DOTFILES_LOCK" 2>/dev/null || echo "unknown")
    lock_caller="${lock_caller:-unknown}"

    # Check if the locking process is still alive
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      warn "[lock] Skipping — locked by $lock_caller (pid $lock_pid)"
      return 1
    fi
    # Stale lock — process is dead, steal it
    warn "[lock] Removing stale lock from $lock_caller (pid $lock_pid)"
    if rm -f "$DOTFILES_LOCK" 2>/dev/null; then
      continue
    fi

    warn "[lock] Cannot remove stale lock at $DOTFILES_LOCK"
    return 1
  done
}

release_lock() {
  # Not used in normal operation — locks are auto-released via the EXIT trap
  # set in acquire_lock(). Kept for manual emergency cleanup in interactive shells:
  #   source lib/lock.sh && release_lock
  rm -f "$DOTFILES_LOCK"
}

# Wait for the dotfiles lock, stealing stale locks like acquire_lock().
# Used by `dotfiles apply` so chezmoi does not race concurrent doctor/sync runs.
wait_for_lock() {
  local caller="${1:-unknown}"
  local max_wait="${2:-120}"
  local waited=0

  while ! acquire_lock "$caller"; do
    if [ "$waited" -ge "$max_wait" ]; then
      local lock_pid lock_caller
      lock_pid=$(head -1 "$DOTFILES_LOCK" 2>/dev/null || echo "?")
      lock_caller=$(sed -n '2p' "$DOTFILES_LOCK" 2>/dev/null || echo "unknown")
      warn "[lock] Timed out after ${max_wait}s — still locked by ${lock_caller} (pid ${lock_pid})"
      return 1
    fi
    sleep 2
    waited=$((waited + 2))
  done
  return 0
}

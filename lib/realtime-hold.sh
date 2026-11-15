# Real-time app hold for periodic jobs.
# Sourced by the dotfiles-sync, tooling-sync and agent-scratch-prune jobs.
# A game stream (GeForce NOW) lags when Git or disk scans run beside it.
# heavy-run already holds builds for the same apps (HEAVY_RUN_PAUSE_APPS).
# These jobs use the same list and skip one run; the next interval retries.
#
# Usage:
#   if app="$(realtime_app_running)"; then echo "skipped: $app"; exit 0; fi
#
# Settings:
#   HEAVY_RUN_PAUSE_APPS     process names, comma-separated (default GeForceNOW;
#                            empty = off)
#   DOTFILES_REALTIME_HOLD   0 = never skip (default 1)
#
# A failed probe counts as "not running": a broken pgrep only removes the
# hold, it never stops maintenance for good.

# realtime_app_running — print the first running real-time app and return 0;
# return 1 when none runs or the hold is off.
realtime_app_running() {
  [ "${DOTFILES_REALTIME_HOLD:-1}" = "0" ] && return 1
  local list="${HEAVY_RUN_PAUSE_APPS-GeForceNOW}" app
  local IFS=,
  for app in $list; do
    [ -n "$app" ] || continue
    if pgrep -x "$app" >/dev/null 2>&1; then
      printf '%s\n' "$app"
      return 0
    fi
  done
  return 1
}

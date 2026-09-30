#!/bin/bash
# Doctor checks for dotfiles sync module

# ── LaunchAgent loaded ──────────────────────────────────────────────
check "sync.launchagent" "sync launchagent loaded" \
  "launchctl list com.dotfiles.dotfiles-sync 2>/dev/null | grep -q Label" \
  ""

# ── Last sync was recent (within 2 hours) ───────────────────────────
STATS_FILE="${DOTFILES_STATS_FILE:-$HOME/.dotfiles-stats.jsonl}"
_last_sync_recent() {
  [ -f "$STATS_FILE" ] || return 1
  local last_ts
  last_ts=$(grep '"task":"sync"' "$STATS_FILE" | tail -1 | grep -o '"timestamp":"[^"]*"' | cut -d'"' -f4)
  [ -n "$last_ts" ] || return 1
  local last_epoch now_epoch
  last_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$last_ts" "+%s" 2>/dev/null) || return 1
  now_epoch=$(date "+%s")
  [ $((now_epoch - last_epoch)) -lt 7200 ]
}
check "sync.recent" "last sync within 2 hours (fix: dotfiles sync)" "_last_sync_recent" ""

# ── No uncommitted dotfiles changes lingering ───────────────────────
check "sync.clean" "no uncommitted dotfiles changes" \
  "[ -z \"\$(git -C '${DOTFILES_LINK_DIR:-$DOTFILES_DIR}' status --porcelain 2>/dev/null)\" ]" \
  ""

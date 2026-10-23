#!/bin/bash
# A small record of updates the background jobs applied (#301), so an agent
# can say "updates landed, run the checkup". The update LaunchAgents
# (tooling-sync, dotfiles-upgrade) apply updates without a word to the agent;
# bin/dotfiles-updates-landed reads this record (an agentbrew SessionStart
# hook can call it), and the checkup acknowledges it with --ack.
#
# Record: ${XDG_STATE_HOME:-~/.local/state}/dotfiles/updates-landed.tsv, one
# "ISO time<TAB>source<TAB>what" line per update, the newest 100 kept.

updates_landed_file() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/updates-landed.tsv"
}

# updates_landed_record <source> <what>: append one line. Never fails the caller.
updates_landed_record() {
  local file tmp
  file="$(updates_landed_file)"
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" >> "$file" 2>/dev/null || return 0
  tmp="$file.tmp.$$"
  tail -n 100 "$file" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
  return 0
}

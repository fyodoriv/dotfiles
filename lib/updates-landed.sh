#!/bin/bash
# A small record of updates the background jobs applied (#301), so an agent
# can say "updates landed, run the checkup". The update LaunchAgents
# (tooling-sync, dotfiles-upgrade) apply updates without a word to the agent;
# bin/dotfiles-updates-landed reads this record (an agentbrew SessionStart
# hook can call it), and the checkup acknowledges it with --ack.
#
# Record: ${XDG_STATE_HOME:-~/.local/state}/dotfiles/updates-landed.tsv, one
# "ISO time<TAB>source<TAB>what" line per update; past 200 lines it is trimmed
# to the newest 100.

updates_landed_file() {
  printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/updates-landed.tsv"
}

# updates_landed_record <source> <what>: append one line. Never fails the caller.
# Writers take a mkdir lock (up to 5 s), so two jobs cannot lose a line.
updates_landed_record() {
  local file tmp lock
  file="$(updates_landed_file)"
  lock="$file.lock"
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  for _ in $(seq 50); do mkdir "$lock" 2>/dev/null && break; sleep 0.1; done
  printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$(printf '%s' "$2" | tr '\t\n' '  ')" >> "$file" 2>/dev/null
  if [ "$(wc -l < "$file" 2>/dev/null || echo 0)" -gt 200 ]; then
    tmp="$file.tmp.$$"
    tail -n 100 "$file" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
  fi
  rmdir "$lock" 2>/dev/null
  return 0
}

# updates_brew_versions: "name version" for every Homebrew formula and cask,
# sorted (nothing without brew). Taken before and after an upgrade.
updates_brew_versions() {
  command -v brew >/dev/null 2>&1 || return 0
  { brew list --formula --versions 2>/dev/null; brew list --cask --versions 2>/dev/null; } | LC_ALL=C sort
}

# updates_version_summary <before> <after>: one short phrase for the versions
# that moved or appeared ("2 Homebrew package(s): foo 1.0 → 1.1, new 0.1
# (new)", at most 5 named); nothing when none did.
updates_version_summary() {
  # The lists go in through the environment: BSD awk -v takes no newlines.
  UL_BEFORE="$1" UL_AFTER="$2" awk 'BEGIN {
    before = ENVIRON["UL_BEFORE"]; after = ENVIRON["UL_AFTER"]
    n = split(before, b, "\n"); for (i = 1; i <= n; i++) if (b[i] != "") { split(b[i], f, " "); old[f[1]] = substr(b[i], length(f[1]) + 2) }
    m = split(after, a, "\n"); count = 0; out = ""
    for (i = 1; i <= m; i++) {
      if (a[i] == "") continue
      split(a[i], f, " "); name = f[1]; ver = substr(a[i], length(name) + 2)
      if (!(name in old)) item = name " " ver " (new)"
      else if (old[name] != ver) item = name " " old[name] " → " ver
      else continue
      count++
      if (count <= 5) out = out (out == "" ? "" : ", ") item
    }
    if (count > 5) out = out ", +" (count - 5) " more"
    if (count > 0) printf "%d Homebrew package(s): %s", count, out
  }'
}

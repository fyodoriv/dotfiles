#!/bin/bash
# List launchd jobs and the heaviest processes, each with an owner and a
# suggested verdict. Read-only: it never loads, unloads, or deletes anything.
#
# Usage: background_audit.sh
#
# Environment:
#   BACKGROUND_AUDIT_DIRS      space-separated plist directories
#                              (default: ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons)
#   BACKGROUND_AUDIT_LAUNCHCTL file holding `launchctl list` output (tests); default runs launchctl
#   BACKGROUND_AUDIT_TOP       how many processes to list by CPU and by memory (default 12; 0 skips)
#   DOTFILES_SOURCE            dotfiles source checkout (default: `chezmoi source-path`)
#
# Owners: apple, dotfiles, agentbrew, minsky, taskgrind (change these in their
# source repo), third-party.
# Verdicts:
#   remove     the job's program does not exist (dangling job)
#   duplicate  another job runs the same program and arguments
#   off-rule   a minsky job is loaded; minsky must never start on its own
#   failing    the job is loaded, not running, and its last exit status is not 0
#   review     third-party job: keep only if the user still uses the app
#   keep       owned by Apple or a tooling repo and healthy

set -uo pipefail

DIRS="${BACKGROUND_AUDIT_DIRS:-$HOME/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons}"
TOP="${BACKGROUND_AUDIT_TOP:-12}"
DOTFILES_SOURCE="${DOTFILES_SOURCE:-$(chezmoi source-path 2>/dev/null || true)}"

if [ -n "${BACKGROUND_AUDIT_LAUNCHCTL:-}" ]; then
  launchd_list="$(cat "$BACKGROUND_AUDIT_LAUNCHCTL")"
else
  launchd_list="$(launchctl list 2>/dev/null || true)"
fi

plist_value() { plutil -extract "$2" raw -o - "$1" 2>/dev/null; }
plist_json() { plutil -extract "$2" json -o - "$1" 2>/dev/null; }

owner_of() {
  local label="$1" file="$2"
  case "$label" in
    com.apple.*) echo apple; return ;;
    com.dotfiles.*) echo dotfiles; return ;;
    com.agentbrew.*) echo agentbrew; return ;;
    com.minsky.*) echo minsky; return ;;
    com.taskgrind.*) echo taskgrind; return ;;
  esac
  if [ -n "$DOTFILES_SOURCE" ] && [ -d "$DOTFILES_SOURCE/launchagents" ] \
      && ls "$DOTFILES_SOURCE/launchagents/$(basename "$file" .plist)".* >/dev/null 2>&1; then
    echo dotfiles
    return
  fi
  echo third-party
}

rows=""
for dir in $DIRS; do
  [ -d "$dir" ] || continue
  for file in "$dir"/*.plist; do
    [ -f "$file" ] || continue
    label="$(plist_value "$file" Label)"
    [ -n "$label" ] || label="$(basename "$file" .plist)"
    program="$(plist_value "$file" Program)"
    [ -n "$program" ] || program="$(plist_value "$file" ProgramArguments.0)"
    command_key="$(plist_json "$file" ProgramArguments)"
    [ -n "$command_key" ] || command_key="$program"
    line="$(printf '%s\n' "$launchd_list" | awk -F'\t' -v l="$label" '$3 == l { print $1 "\t" $2; exit }')"
    pid="${line%%$'\t'*}"
    status="${line#*$'\t'}"
    [ -n "$line" ] || { pid="-"; status="unloaded"; }
    owner="$(owner_of "$label" "$file")"
    rows="$rows$label"$'\t'"$owner"$'\t'"$pid"$'\t'"$status"$'\t'"$program"$'\t'"$command_key"$'\t'"$file"$'\n'
  done
done

echo "== launchd jobs"
if [ -z "$rows" ]; then
  echo "  (none found in: $DIRS)"
else
  printf '%s' "$rows" | awk -F'\t' '
    { label[NR] = $1; owner[NR] = $2; pid[NR] = $3; status[NR] = $4; prog[NR] = $5; key[NR] = $6; file[NR] = $7; count[$6]++ }
    END {
      for (i = 1; i <= NR; i++) {
        verdict = "keep"
        if (owner[i] == "third-party") verdict = "review"
        if (pid[i] == "-" && status[i] != "unloaded" && status[i] != "0") verdict = "failing"
        if (owner[i] == "minsky" && status[i] != "unloaded") verdict = "off-rule"
        if (key[i] != "" && count[key[i]] > 1) verdict = "duplicate"
        if (prog[i] ~ /^\// && system("test -e \"" prog[i] "\"") != 0) verdict = "remove"
        state = (status[i] == "unloaded") ? "unloaded" : "pid=" pid[i] " last_exit=" status[i]
        printf "  %-9s %-11s %s %s program=%s plist=%s\n", verdict, owner[i], label[i], state, (prog[i] == "" ? "?" : prog[i]), file[i]
      }
    }' | sort
fi

[ "$TOP" = "0" ] && exit 0

echo "== top $TOP processes by CPU"
ps -Ao pid=,pcpu=,rss=,etime=,comm= -r 2>/dev/null | head -n "$TOP" \
  | awk '{ printf "  pid=%s cpu=%s%% rss_mb=%.0f up=%s %s\n", $1, $2, $3 / 1024, $4, $5 }'
echo "== top $TOP processes by memory"
ps -Ao pid=,pcpu=,rss=,etime=,comm= -m 2>/dev/null | head -n "$TOP" \
  | awk '{ printf "  pid=%s cpu=%s%% rss_mb=%.0f up=%s %s\n", $1, $2, $3 / 1024, $4, $5 }'
echo "== load"
uptime

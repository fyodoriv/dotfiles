#!/bin/bash
# What a LaunchAgent plist says it runs, and what launchd runs for it.
# Used by bin/dotfiles-launchagent-drift (#297) and bin/dotfiles-reload-launchagents (#310).
# LAUNCHCTL overrides the launchctl command (tests).

# launchagent_plist_args <plist>: ProgramArguments, one per line (or Program).
launchagent_plist_args() {
  local i=0 v
  if /usr/bin/plutil -extract ProgramArguments.0 raw -o - "$1" >/dev/null 2>&1; then
    while v="$(/usr/bin/plutil -extract "ProgramArguments.$i" raw -o - "$1" 2>/dev/null)"; do
      printf '%s\n' "$v"; i=$((i + 1))
    done
  else
    /usr/bin/plutil -extract Program raw -o - "$1" 2>/dev/null
  fi
}

# launchagent_loaded_args <print output>: the "arguments = { ... }" lines,
# one per line; for a job without them, its "program =" line.
launchagent_loaded_args() {
  local args
  args="$(awk '/^\targuments = \{$/ { inside = 1; next } inside && /^\t\}$/ { exit } inside { sub(/^\t\t/, ""); print }' <<< "$1")"
  [ -n "$args" ] || args="$(sed -n 's/^\tprogram = //p' <<< "$1" | head -n 1)"
  printf '%s\n' "$args"
}

# launchagent_plist_env <plist>: its EnvironmentVariables as "KEY => VALUE"
# lines, sorted (needs jq; fails without it).
launchagent_plist_env() {
  command -v jq >/dev/null 2>&1 || return 1
  /usr/bin/plutil -convert json -o - "$1" 2>/dev/null |
    jq -r '(.EnvironmentVariables // {}) | to_entries[] | "\(.key) => \(.value)"' | LC_ALL=C sort
}

# launchagent_loaded_env <print output>: the "environment = { ... }" lines.
launchagent_loaded_env() {
  awk '/^\tenvironment = \{$/ { inside = 1; next } inside && /^\t\}$/ { exit } inside { sub(/^\t\t/, ""); print }' <<< "$1" | LC_ALL=C sort
}

# launchagent_running_unchanged <domain> <label> <plist>: succeeds when the
# job is loaded, running, runs exactly its plist's arguments, and has each
# of its plist's environment variables (launchd adds its own, so the plist's
# are a subset). When the environment cannot be compared, it fails, so the
# caller reloads.
launchagent_running_unchanged() {
  local out want
  out="$("${LAUNCHCTL:-launchctl}" print "$1/$2" 2>/dev/null)" || return 1
  [ "$(sed -n 's/^\tstate = //p' <<< "$out" | head -n 1)" = running ] || return 1
  [ "$(launchagent_loaded_args "$out")" = "$(launchagent_plist_args "$3")" ] || return 1
  want="$(launchagent_plist_env "$3")" || return 1
  [ -z "$want" ] || [ -z "$(LC_ALL=C comm -23 <(printf '%s\n' "$want") <(launchagent_loaded_env "$out"))" ]
}

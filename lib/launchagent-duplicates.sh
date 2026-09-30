#!/bin/bash
# Find LaunchAgents that duplicate a dotfiles-managed job.
#
# dotfiles owns every com.dotfiles.* agent. An older install may have left
# a copy under another label prefix, or someone installed one by hand. That
# copy runs the same job twice: two opencode servers on one port, two doctor
# runs, two sync pushes. An agent outside com.dotfiles.* is a duplicate when
#
#   1. its command line is identical to an installed com.dotfiles.* agent, or
#   2. its command runs a script from the dotfiles checkout.
#
# Rule 2 means dotfiles scripts only ever run from managed agents.
#
# An agent that only shares a managed agent's name suffix (for example
# `<prefix>.gui-path` with a different command) is reported as a possible
# duplicate. It is never removed automatically: the suffix alone could
# match a Homebrew service such as `homebrew.mxcl.ollama`.
#
# Usage (sourced):
#   source lib/launchagent-duplicates.sh
#   launchagent_duplicates "$HOME/Library/LaunchAgents" "$DOTFILES_DIR"
#   launchagent_suffix_twins "$HOME/Library/LaunchAgents"

# Print the command line of a plist, one argument per line. Prints nothing
# (and still succeeds) for a plist without ProgramArguments or Program, so
# callers running under `set -e` keep scanning.
launchagent_argv() {
  local plist="$1" out
  if out="$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments' "$plist" 2>/dev/null)"; then
    printf '%s\n' "$out" | sed -e '1d' -e '$d' -e 's/^    //'
    return 0
  fi
  /usr/libexec/PlistBuddy -c 'Print :Program' "$plist" 2>/dev/null || true
}

# Print the label of every duplicate agent in <dir>, one per line.
launchagent_duplicates() {
  local dir="$1" dotfiles_dir="$2" plist name argv managed_hashes=""
  for plist in "$dir"/com.dotfiles.*.plist; do
    [ -f "$plist" ] || continue
    managed_hashes+="$(launchagent_argv "$plist" | shasum | cut -d' ' -f1)"$'\n'
  done
  for plist in "$dir"/*.plist; do
    [ -f "$plist" ] || continue
    name="$(basename "$plist" .plist)"
    case "$name" in com.dotfiles.*) continue ;; esac
    argv="$(launchagent_argv "$plist")"
    [ -n "$argv" ] || continue
    if grep -qxF -- "$(printf '%s\n' "$argv" | shasum | cut -d' ' -f1)" <<<"$managed_hashes" ||
      grep -qF -- "${dotfiles_dir%/}/" <<<"$argv"; then
      printf '%s\n' "$name"
    fi
  done
}

# Print "<label> <managed twin>" for agents outside com.dotfiles.* whose
# name ends like a managed agent but whose command differs.
launchagent_suffix_twins() {
  local dir="$1" plist name managed short
  for plist in "$dir"/*.plist; do
    [ -f "$plist" ] || continue
    name="$(basename "$plist" .plist)"
    case "$name" in com.dotfiles.*) continue ;; esac
    for managed in "$dir"/com.dotfiles.*.plist; do
      [ -f "$managed" ] || continue
      short="$(basename "$managed" .plist)"
      short="${short#com.dotfiles.}"
      if [[ "$name" == *".$short" ]]; then
        printf '%s %s\n' "$name" "com.dotfiles.$short"
      fi
    done
  done
}

# Unload and delete the duplicate agents in <dir>, plus their backup files.
launchagent_remove_duplicates() {
  local dir="$1" dotfiles_dir="$2" name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    echo "⊘ Unloading duplicate: $name"
    launchctl unload "$dir/$name.plist" 2>/dev/null || true
    rm -f "$dir/$name.plist" "$dir/$name.plist".backup*
  done < <(launchagent_duplicates "$dir" "$dotfiles_dir")
}

# Unload and delete renamed debug-Chrome agents in <dir>. The debug Chrome
# label is `com.dotfiles.debug-chrome`. An older install may still hold a
# `com.dotfiles.<prefix>-debug-chrome` agent that also owns port 9224.
# Matching by glob keeps the old name out of this repo.
launchagent_remove_renamed_debug_chrome() {
  local dir="$1" plist name
  for plist in "$dir"/com.dotfiles.*-debug-chrome.plist; do
    [ -f "$plist" ] || continue
    name="$(basename "$plist" .plist)"
    [ "$name" = "com.dotfiles.debug-chrome" ] && continue
    echo "⊘ Unloading renamed debug Chrome agent: $name"
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist" "$plist".backup*
  done
}

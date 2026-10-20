#!/bin/bash
# Core options for the purpose Chrome LaunchAgent (issue #145, step 7).
# These replace overlay post-patches of the rendered plist:
#   chrome.purpose_headed   true  → drop --headless=new (a visible window)
#   chrome.restore_session  true  → add --restore-last-session
#   chrome.dock_guard       false → no com.dotfiles.chrome-dock-guard (#237)
# Values come from config/plugin-options.yaml (default false) and plugins.

# _chrome_args_index <plist> <arg>: prints the ProgramArguments index of
# <arg>, or fails.
_chrome_args_index() {
  local i=0 v
  while v="$(plutil -extract "ProgramArguments.$i" raw -o - "$1" 2>/dev/null)"; do
    [ "$v" = "$2" ] && { printf '%s' "$i"; return 0; }
    i=$((i + 1))
  done
  return 1
}

# chrome_purpose_apply_options <plist> <headed:true|false> <restore:true|false>
chrome_purpose_apply_options() {
  local plist="$1" headed="$2" restore="$3" idx count
  if [ "$headed" = true ] && idx="$(_chrome_args_index "$plist" --headless=new)"; then
    plutil -remove "ProgramArguments.$idx" "$plist"
  fi
  if [ "$restore" = true ] && ! _chrome_args_index "$plist" --restore-last-session >/dev/null; then
    count="$(plutil -extract ProgramArguments raw -o - "$plist")"
    plutil -insert "ProgramArguments.$count" -string --restore-last-session "$plist"
  fi
}

# chrome_dock_guard_enabled <dock_guard:true|false> <headed:true|false>
# Succeeds when the Dock guard should run. A headless purpose Chrome has no
# window, so a Dock click can get stuck in it: the guard stays on there.
chrome_dock_guard_enabled() {
  [ "$1" = false ] && [ "$2" = true ] && return 1
  return 0
}

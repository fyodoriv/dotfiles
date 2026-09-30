#!/bin/bash
# Shared grep helpers for focus-steal doctor checks.
# Vision G1: recurring focus steals become failing doctor checks.

focus_steal_audit_paths() {
  printf '%s\n' \
    "$DOTFILES_DIR/bin" \
    "$DOTFILES_DIR/lib" \
    "$DOTFILES_DIR/launchagents" \
    "$DOTFILES_DIR/macos-apps.sh"
}

# Lines that mention open -a without -g / --background / --gj (comment lines excluded).
focus_steal_open_a_violations() {
  local path violations=""
  while IFS= read -r path; do
    [ -e "$path" ] || continue
    if [ -d "$path" ]; then
      violations+=$(grep -RnE '\bopen -a' "$path" 2>/dev/null \
        | grep -vE '(^([^:]+:)?[0-9]+:[[:space:]]*(#|--)|[- ]g[j]?|--background|--gj)' || true)
    else
      violations+=$(grep -nE '\bopen -a' "$path" 2>/dev/null \
        | grep -vE '(^([^:]+:)?[0-9]+:[[:space:]]*(#|--)|[- ]g[j]?|--background|--gj)' \
        | sed "s|^|$path:|" || true)
    fi
  done < <(focus_steal_audit_paths)
  if [ -n "$violations" ]; then
    printf '%s\n' "$violations"
  fi
}

# osascript / AppleScript activate (comment lines and echo help excluded).
focus_steal_activate_violations() {
  local path violations=""
  while IFS= read -r path; do
    [ -e "$path" ] || continue
    if [ -d "$path" ]; then
      violations+=$(grep -RnE 'to activate' "$path" 2>/dev/null \
        | grep -vE 'focus-steal-audit\.sh:[0-9]+:' \
        | grep -vE 'chromework-install:[0-9]+:' \
        | grep -vE 'chromework-activate:[0-9]+:' \
        | grep -vE '(^[^:]*:[0-9]+:#|#.*to activate|echo .*Restart Chrome to activate|Restart Chrome to activate|failed to activate)' || true)
    else
      violations+=$(grep -nE 'to activate' "$path" 2>/dev/null \
        | grep -vE 'focus-steal-audit\.sh:[0-9]+:' \
        | grep -vE 'chromework-install:[0-9]+:' \
        | grep -vE 'chromework-activate:[0-9]+:' \
        | grep -vE '(^[^:]*:[0-9]+:#|#.*to activate|echo .*Restart Chrome to activate|Restart Chrome to activate|failed to activate)' \
        | sed "s|^|$path:|" || true)
    fi
  done < <(focus_steal_audit_paths)
  if [ -n "$violations" ]; then
    printf '%s\n' "$violations"
  fi
}

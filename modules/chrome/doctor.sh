#!/bin/bash
# Doctor checks for Chrome module
#
# Work-profile routing is enforced on two complementary axes (both enterprise-
# only — they need the configured work_email_domain to detect which profile
# dir is Work):
#
#   chrome.default_profile      Cold launches → patches Local State so a
#                               freshly-started Chrome opens the Work profile.
#                               Fix command: bin/chrome-enforce-profile.
#
#   chrome.chromework_router    Already-running Chrome → routes every http(s)
#                               URL to the Work profile via a dedicated
#                               ~/Applications/ChromeWork.app that invokes
#                               Chrome's binary with explicit --user-data-dir,
#                               bypassing LaunchServices' "which Chrome wins"
#                               ambiguity when agent-browser Chrome daemons
#                               (com.dotfiles.{agent-browser,debug-chrome,
#                               tooling}-chrome) run from the same bundle.
#                               Fix command: bin/chromework-install --force.
#
#   chrome.default_browser      ChromeWork is the system http(s) handler (enterprise).
#                               Reasserted on every chromework-install / chrome-heal.
#                               Fix command: chromework-install
#
# Both axes are reasserted hourly by com.dotfiles.chrome-profile via
# bin/chrome-heal (and on every /ship-it Step 12 `dotfiles doctor --module chrome --fix`).
#
# When Chrome isn't installed locally both checks are silently skipped — the
# Python helper would otherwise emit a misleading FileNotFoundError on the
# missing Local State file.

LOCAL_STATE="$HOME/Library/Application Support/Google/Chrome/Local State"
WORK_EMAIL_DOMAIN="$(chezmoi execute-template '{{ .work_email_domain }}' 2>/dev/null || echo "example.com")"
# Override CHROME_APP_DIR in tests to simulate Chrome-not-installed.
CHROME_APP_DIR="${CHROME_APP_DIR:-/Applications/Google Chrome.app}"

# Returns 0 when Chrome's last-used profile is the work profile and the
# profile picker is not configured to show on startup. Args:
#   $1: path to Chrome's `Local State` JSON file
#   $2: work email domain expected in the last-used profile's user_name
# Failure cases (returns 1):
#   • Local State file missing or unreadable
#   • Last-used profile's user_name does not contain the work domain
#   • show_picker_on_startup is not explicitly false
_chrome_default_profile_matches() {
  local state="$1" domain="$2"
  [ -f "$state" ] || return 1
  local last user_name picker
  last=$(jq -r '.profile.last_used // empty' "$state" 2>/dev/null) || return 1
  [ -n "$last" ] || return 1
  user_name=$(jq -r --arg p "$last" '.profile.info_cache[$p].user_name // empty' "$state") || return 1
  case "$user_name" in *"$domain"*) ;; *) return 1 ;; esac
  picker=$(jq '.profile.show_picker_on_startup' "$state") || return 1
  [ "$picker" = "false" ] || return 1
}

if [ "$IS_ENTERPRISE" = "true" ] && [ -d "$CHROME_APP_DIR" ]; then
  check "chrome.default_profile" "Chrome opens with Work profile" \
    "_chrome_default_profile_matches \"$LOCAL_STATE\" \"$WORK_EMAIL_DOMAIN\"" \
    "chrome-enforce-profile"
fi

# Returns 0 when ~/Applications/ChromeWork.app is present and its compiled
# AppleScript routes URLs through Chrome's binary with an explicit
# --user-data-dir (so agent-browser Chrome daemons can't steal URLs) and a
# --profile-directory pointing at the work profile detected from Local State.
# Args:
#   $1: work email domain expected in the last-used profile's user_name
# Failure cases (returns 1):
#   • ChromeWork.app missing
#   • osadecompile fails to read the bundle
#   • AppleScript lacks --user-data-dir= (router falls back to `open -a` ambiguity)
#   • AppleScript's --profile-directory= doesn't match the detected work profile
_chromework_router_correct() {
  local domain="$1"
  local app="$HOME/Applications/ChromeWork.app"
  local open_helper="${DOTFILES_LINK_DIR:-${DOTFILES_DIR:-$HOME/apps/tooling/dotfiles}}/bin/chromework-open-url"
  [ -d "$app" ] || return 1
  [ -x "$open_helper" ] || return 1
  local startup
  startup="$(plutil -extract OSAAppletShowStartupScreen raw "$app/Contents/Info.plist" 2>/dev/null || echo "missing")"
  [ "$startup" = "false" ] || return 1
  local ui_element
  ui_element="$(plutil -extract LSUIElement raw "$app/Contents/Info.plist" 2>/dev/null || echo "missing")"
  [ "$ui_element" = "true" ] || return 1
  local decompiled
  decompiled=$(osadecompile "$app" 2>/dev/null) || return 1
  echo "$decompiled" | grep -q 'chromework-open-url' || return 1
  echo "$decompiled" | grep -Fq "$open_helper" || return 1
  echo "$decompiled" | grep -q 'on activateWorkChrome' || return 1
  echo "$decompiled" | grep -q 'chromework-activate' || return 1
  echo "$decompiled" | grep -q -- '--survive-handoff' || return 1
  echo "$decompiled" | grep -q -- '--no-activate' || return 1
  echo "$decompiled" | grep -q -- "--user-data-dir=" && return 1
  echo "$decompiled" | grep -q 'on workChromeHasVisibleWindows' && return 1
  return 0
}

if [ "$IS_ENTERPRISE" = "true" ] && [ -d "$CHROME_APP_DIR" ]; then
  check "chrome.chromework_router" "ChromeWork URL router built for current profile" \
    "_chromework_router_correct \"$WORK_EMAIL_DOMAIN\"" \
    "chromework-install --force"
fi

# Returns 0 when defaultbrowser reports ChromeWork ("browser") as the active
# http(s) handler. Slack, Outlook, Mail, etc. all use this system default.
_chromework_is_default_browser() {
  command -v defaultbrowser &>/dev/null || return 1
  local current
  current="$(defaultbrowser 2>/dev/null | awk '/^\*/ {print $2; exit}')"
  [ "$current" = "browser" ]
}

if [ "$IS_ENTERPRISE" = "true" ] && [ -d "$CHROME_APP_DIR" ]; then
  check "chrome.default_browser" "ChromeWork is system default browser for http(s)" \
    "_chromework_is_default_browser" \
    "chromework-install"
fi

# Chrome dev settings applied
check_defaults "chrome.devtools" "Chrome DevTools always available" \
  com.google.Chrome DevToolsAvailability "1" int

check_defaults "chrome.full_urls" "Chrome full URLs in address bar" \
  com.google.Chrome ShowFullURLsInAddressBar "1" bool

check_defaults "chrome.swipe_nav" "Chrome swipe navigation disabled" \
  com.google.Chrome AppleEnableSwipeNavigateWithScrolls "0" bool

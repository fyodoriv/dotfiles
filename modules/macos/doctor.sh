#!/bin/bash
# Doctor checks for macos module

pmset_custom_value_is() {
  local profile="$1" key="$2" expected="$3"
  pmset -g custom 2>/dev/null | awk -v profile="$profile" -v key="$key" -v expected="$expected" '
    $0 == profile ":" { in_profile = 1; next }
    /^[^[:space:]].*:$/ { in_profile = 0 }
    in_profile && $1 == key { found = 1; ok = ($2 == expected); exit }
    END { exit(found && ok ? 0 : 1) }
  '
}

# ── Performance: Animations ──────────────────────────────────────────
check_defaults "macos.window_animations"  "Window animations off"        NSGlobalDomain NSAutomaticWindowAnimationsEnabled "0" bool
check_defaults "macos.scroll_animations"  "Scroll animations off"        NSGlobalDomain NSScrollAnimationEnabled           "0" bool
check_defaults "macos.resize_time"        "Window resize instant"        NSGlobalDomain NSWindowResizeTime                 "0.001" float

# ── Keyboard ─────────────────────────────────────────────────────────
check_defaults "macos.key_repeat"         "Key repeat = 1 (fastest)"     NSGlobalDomain KeyRepeat                          "1" int
check_defaults "macos.initial_key_repeat" "Initial key repeat = 15"      NSGlobalDomain InitialKeyRepeat                   "15" int
check_defaults "macos.press_and_hold"     "Press-and-hold disabled"      NSGlobalDomain ApplePressAndHoldEnabled            "0" bool
check_defaults "macos.autocorrect"        "Auto-correct off"             NSGlobalDomain NSAutomaticSpellingCorrectionEnabled "0" bool
check_defaults "macos.autocapitalize"     "Auto-capitalize off"          NSGlobalDomain NSAutomaticCapitalizationEnabled     "0" bool
check_defaults "macos.smartquotes"        "Smart quotes off"             NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled  "0" bool
check_defaults "macos.smartdashes"        "Smart dashes off"             NSGlobalDomain NSAutomaticDashSubstitutionEnabled   "0" bool
check_defaults "macos.period_substitution" "Period substitution off"     NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled "0" bool
check_defaults "macos.text_completion"    "Text completion popups off"   NSGlobalDomain NSAutomaticTextCompletionEnabled     "0" bool

# ── Dock ─────────────────────────────────────────────────────────────
check_defaults "macos.dock_autohide"      "Dock autohide enabled"        com.apple.dock autohide                "1" bool
check_defaults "macos.dock_autohide_delay" "Dock autohide delay = 0"     com.apple.dock autohide-delay          "0" float
check_defaults "macos.dock_launch_anim"   "Dock launch animation off"    com.apple.dock launchanim              "0" bool
check_defaults "macos.dock_minimize"      "Minimize to app"              com.apple.dock minimize-to-application  "1" bool
check_defaults "macos.dock_mru"           "Don't rearrange Spaces"       com.apple.dock mru-spaces              "0" bool
check_defaults "macos.dock_recents"       "Hide recent apps in Dock"     com.apple.dock show-recents            "0" bool
check_defaults "macos.dock_expose_speed"  "Expose animation fast"        com.apple.dock expose-animation-duration "0.1" float

# ── App Nap ──────────────────────────────────────────────────────────
check_defaults "macos.app_nap"            "App Nap disabled"             NSGlobalDomain NSAppSleepDisabled      "1" bool

# ── Finder ───────────────────────────────────────────────────────────
check_defaults "macos.finder_hidden_files"  "Finder shows hidden files"  com.apple.finder AppleShowAllFiles         "1" bool
check_defaults "macos.finder_pathbar"       "Finder path bar"            com.apple.finder ShowPathbar               "1" bool
check_defaults "macos.finder_statusbar"     "Finder status bar"          com.apple.finder ShowStatusBar             "1" bool
check_defaults "macos.finder_folders_first" "Folders first"              com.apple.finder _FXSortFoldersFirst       "1" bool
check_defaults "macos.finder_extensions"    "Show all extensions"        NSGlobalDomain   AppleShowAllExtensions    "1" bool
check_defaults "macos.finder_no_anim"       "Finder animations off"      com.apple.finder DisableAllAnimations      "1" bool
check_defaults "macos.finder_ext_warning"   "No extension change warning" com.apple.finder FXEnableExtensionChangeWarning "0" bool
check_defaults "macos.finder_search_scope"  "Search current folder"      com.apple.finder FXDefaultSearchScope      "SCcf" string
check_defaults "macos.finder_column_view"   "Column view default"        com.apple.finder FXPreferredViewStyle      "clmv" string
check_defaults "macos.finder_no_desktop"    "No desktop icons"           com.apple.finder CreateDesktop             "0" bool

# ── DS_Store ─────────────────────────────────────────────────────────
check_defaults "macos.no_ds_store_network"  "No .DS_Store on network"    com.apple.desktopservices DSDontWriteNetworkStores "1" bool
check_defaults "macos.no_ds_store_usb"      "No .DS_Store on USB"        com.apple.desktopservices DSDontWriteUSBStores     "1" bool

# ── Misc ─────────────────────────────────────────────────────────────
check_defaults "macos.crash_reporter"     "Crash reporter silent"        com.apple.CrashReporter DialogType              "none" string
check_defaults "macos.save_to_disk"       "Save to disk (not iCloud)"    NSGlobalDomain  NSDocumentSaveNewDocumentsToCloud "0" bool
check_defaults "macos.expand_save"        "Expanded save panel"          NSGlobalDomain  NSNavPanelExpandedStateForSaveMode "1" bool
if [ "${DOTFILES_PROFILE:-full}" = "full" ]; then
  check_defaults "macos.no_quarantine"    "No quarantine warnings"       com.apple.LaunchServices LSQuarantine           "0" bool
fi

# ── Screenshots ──────────────────────────────────────────────────────
check_defaults "macos.screenshot_type"    "Screenshot format = PNG"      com.apple.screencapture type            "png" string
check_defaults "macos.screenshot_shadow"  "No screenshot shadow"         com.apple.screencapture disable-shadow  "1" bool

# ── Mouse ────────────────────────────────────────────────────────────
check_defaults "macos.mouse_speed"        "Mouse tracking speed = 3"     NSGlobalDomain com.apple.mouse.scaling                "3" float

# ── Trackpad ─────────────────────────────────────────────────────────
check_defaults "macos.trackpad_speed"     "Trackpad tracking speed = 3"  NSGlobalDomain com.apple.trackpad.scaling             "3" float
check_defaults "macos.tap_to_click"       "Tap to click"                 com.apple.AppleMultitouchTrackpad Clicking             "1" bool
check_defaults "macos.three_finger_drag"  "Three-finger drag"            com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag "1" bool

# ── Window management ────────────────────────────────────────────────
check_defaults "macos.tiling_edge"        "Window tiling by edge drag"   com.apple.WindowManager EnableTilingByEdgeDrag "1" bool

# ── Security ─────────────────────────────────────────────────────────
check_defaults "macos.password_after_sleep" "Password after sleep"       com.apple.screensaver askForPassword    "1" int
check_defaults "macos.password_after_sleep_delay" "Password delay = 0"   com.apple.screensaver askForPasswordDelay "0" int
check_defaults "macos.screensaver_idle_time" "Screen saver starts at 15 min" com.apple.screensaver idleTime        "900" int

check "macos.pmset_display_sleep_15" "Display sleep = 15 min on AC and battery" \
  "! command -v pmset >/dev/null || { pmset_custom_value_is 'AC Power' displaysleep 15 && pmset_custom_value_is 'Battery Power' displaysleep 15; }" \
  "sudo -n pmset -a displaysleep 15"
check "macos.pmset_battery_sleep_15" "Battery system sleep = 15 min" \
  "! command -v pmset >/dev/null || pmset_custom_value_is 'Battery Power' sleep 15" \
  "sudo -n pmset -b sleep 15"
check "macos.pmset_battery_disk_sleep_15" "Battery disk sleep = 15 min" \
  "! command -v pmset >/dev/null || pmset_custom_value_is 'Battery Power' disksleep 15" \
  "sudo -n pmset -b disksleep 15"
check "macos.pmset_ac_sleep_1" "AC system sleep = 1 min when no agent is running" \
  "! command -v pmset >/dev/null || pmset_custom_value_is 'AC Power' sleep 1" \
  "sudo -n pmset -c sleep 1"
check "macos.pmset_ac_disk_sleep_10" "AC disk sleep = 10 min when no agent is running (who reset it: ~/.local/share/dotfiles/logs/pmset-drift.log)" \
  "! command -v pmset >/dev/null || pmset_custom_value_is 'AC Power' disksleep 10" \
  "sudo -n pmset -c disksleep 10"

# ── Dynamic checks (require conditional logic) ───────────────────────
check "macos.dock_no_static_only" "Dock static-only disabled (shows folders)" \
  "[ \"$(defaults read com.apple.dock static-only 2>/dev/null)\" != '1' ]" \
  "defaults delete com.apple.dock static-only 2>/dev/null; killall Dock 2>/dev/null"

# ── Dock folders ─────────────────────────────────────────────────────
if command -v dockutil &>/dev/null; then
  check "macos.dock_applications" "Dock: Applications folder" \
    "dockutil --find Applications 2>/dev/null | grep -q persistent-others" \
    "dockutil --add /Applications --view grid --display folder --sort name --no-restart && killall Dock 2>/dev/null"
  check "macos.dock_downloads" "Dock: Downloads folder" \
    "dockutil --find Downloads 2>/dev/null | grep -q persistent-others" \
    "dockutil --add \"\$HOME/Downloads\" --view grid --display stack --sort dateadded --no-restart && killall Dock 2>/dev/null"
fi

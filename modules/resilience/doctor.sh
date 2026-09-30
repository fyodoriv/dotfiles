#!/bin/bash
# Doctor checks for the agent-resilience layer.
#
# Verifies that the "agents survive lid close + network drops + terminal close"
# stack is loaded and healthy. The stack lives at the intersection of:
#   - tmux (session persistence for agent CLIs)
#   - sleepwatcher (~/.sleep + ~/.wakeup hooks)
#   - network-watchdog (auto-heal wifi/VPN/DNS post-wake)
#   - process-scoped caffeinate and Amphetamine (Cursor/Claude Code only)
#   - normal macOS idle timers when no tracked agent process is running
#
# Run `dotfiles-resilience-setup` for the install/configure wizard.

# shellcheck source=../../lib/agent-keepawake.sh
source "$DOTFILES_DIR/lib/agent-keepawake.sh"

# ── tmux ──────────────────────────────────────────────────────────────
check "resilience.tmux_installed" "tmux installed (session persistence for agents)" \
  "command -v tmux >/dev/null 2>&1" \
  "echo 'Install: brew install tmux'"

check "resilience.agent_tmux_executable" "agent-tmux wrapper is executable" \
  "[ -x \"\$DOTFILES_DIR/bin/agent-tmux\" ]" \
  "chmod +x \"\$DOTFILES_DIR/bin/agent-tmux\""

# ── sleepwatcher ──────────────────────────────────────────────────────
check "resilience.sleepwatcher_binary" "sleepwatcher binary present" \
  "[ -x /opt/homebrew/sbin/sleepwatcher ] || [ -x /usr/local/sbin/sleepwatcher ]" \
  "echo 'Install: brew install sleepwatcher'"

check "resilience.sleepwatcher_loaded" "sleepwatcher LaunchAgent loaded" \
  "launchctl list 2>/dev/null | grep -q com.dotfiles.sleepwatcher" \
  "echo 'Load: launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist'"

check "resilience.wakeup_hook_exists" '$HOME/.wakeup hook fires network-watchdog' \
  "[ -f \"\$HOME/.wakeup\" ] && grep -q 'network-watchdog' \"\$HOME/.wakeup\"" \
  "echo 'Re-apply dotfiles to restore: dotfiles apply'"

# ── network-resilience LaunchAgent ────────────────────────────────────
# Stale-path detection: the agent was firing exit-127 errors after the
# repo moved from ~/apps/dotfiles to ~/apps/tooling/dotfiles. The fix
# was launchctl bootout+bootstrap; this check catches future regressions.
check "resilience.network_watchdog_clean" "network-resilience LaunchAgent exit code is clean (not 127)" \
  "! launchctl print gui/\$UID/com.dotfiles.network-resilience 2>/dev/null | grep -q 'last exit code = 127'" \
  "echo 'Reload: launchctl bootout gui/\$UID/com.dotfiles.network-resilience && launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/com.dotfiles.network-resilience.plist'"

check "resilience.network_watchdog_loaded" "network-resilience LaunchAgent loaded" \
  "launchctl list 2>/dev/null | grep -q com.dotfiles.network-resilience" \
  "echo 'Load: launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/com.dotfiles.network-resilience.plist'"

# ── mas (App Store CLI — needed for Amphetamine install) ──────────────
check "resilience.mas_installed" "mas (App Store CLI) installed" \
  "command -v mas >/dev/null 2>&1" \
  "echo 'Install: brew install mas'"

# ── Amphetamine (lid-close persistence on AC) ─────────────────────────
# Soft check — Amphetamine is App Store only and requires user sign-in,
# so we don't try to auto-install. The setup wizard
# (dotfiles-resilience-setup) opens the App Store page and prints
# trigger config instructions on first run.
check "resilience.amphetamine_installed" "Amphetamine.app installed (lid-close persistence)" \
  "[ -d /Applications/Amphetamine.app ]" \
  "echo 'Run: dotfiles-resilience-setup (will open App Store + print config steps)'"

# A stale manual Single-Use session can survive for days, continuously
# preventing system sleep (and, depending on its setting, display sleep).
# Deliberate Trigger sessions use their own lifecycle, so only inspect the
# Single-Use assertions here.
_amphetamine_no_stale_single_use_assertion() {
  local app_path="${AMPHETAMINE_APP_PATH:-/Applications/Amphetamine.app}"
  local max_hours="${AMPHETAMINE_DISPLAY_SLEEP_MAX_HOURS:-12}"
  local max_seconds elapsed hours minutes seconds elapsed_seconds
  [ -d "$app_path" ] || return 0
  command -v pmset >/dev/null 2>&1 || return 0
  # The manager records the session it creates. A valid marker with a live
  # qualifying Cursor/Claude process is an intentional long-running session,
  # not a forgotten manual Single-Use session.
  if declare -F dotfiles_agent_amphetamine_session_is_owned >/dev/null \
      && dotfiles_agent_amphetamine_session_is_owned; then
    return 0
  fi
  [[ "$max_hours" =~ ^[1-9][0-9]*$ ]] || max_hours=12
  max_seconds=$((10#$max_hours * 3600))

  while IFS= read -r elapsed; do
    [[ "$elapsed" =~ ^[0-9]+:[0-5][0-9]:[0-5][0-9]$ ]] || continue
    IFS=: read -r hours minutes seconds <<< "$elapsed"
    elapsed_seconds=$((10#$hours * 3600 + 10#$minutes * 60 + 10#$seconds))
    (( elapsed_seconds < max_seconds )) || return 1
  done < <(pmset -g assertions 2>/dev/null | awk '/pid [0-9]+\(Amphetamine\):/ && /PreventUserIdle(System|Display)Sleep/ && /named: "Amphetamine \(Single-Use/ { print $4 }')
  return 0
}

check_advisory "resilience.amphetamine_stale_single_use" "No stale Amphetamine Single-Use sleep-prevention assertion (12h default)" \
  "_amphetamine_no_stale_single_use_assertion" \
  "osascript -e 'tell application \"Amphetamine\" to end session'"

# Amphetamine must not own generic automatic sessions. The process manager
# starts one only for live Cursor/Claude Code work, then ends its own session.
_amphetamine_managed_session_policy() {
  local app_path="${AMPHETAMINE_APP_PATH:-/Applications/Amphetamine.app}"
  local trigger_count triggers_enabled at_launch on_wake on_ac_reconnect
  [ -d "$app_path" ] || return 0
  trigger_count="$(defaults read com.if.Amphetamine 'Trigger Data' 2>/dev/null | { grep -c '{' || true; })"
  [[ "$trigger_count" =~ ^[0-9]+$ ]] || trigger_count=0
  triggers_enabled="$(defaults read com.if.Amphetamine 'Enable Triggers' 2>/dev/null || echo 0)"
  at_launch="$(defaults read com.if.Amphetamine 'Start Session At Launch' 2>/dev/null || echo 0)"
  on_wake="$(defaults read com.if.Amphetamine 'Start Session On Wake' 2>/dev/null || echo 0)"
  on_ac_reconnect="$(defaults read com.if.Amphetamine 'Restart DD Session on AC Reconnect' 2>/dev/null || echo 0)"
  [ "$trigger_count" -eq 0 ] \
    && [ "$triggers_enabled" != "1" ] \
    && [ "$at_launch" != "1" ] \
    && [ "$on_wake" != "1" ] \
    && [ "$on_ac_reconnect" != "1" ]
}

_amphetamine_apply_managed_session_policy() {
  defaults write com.if.Amphetamine 'Start Session At Launch' -bool false &&
    defaults write com.if.Amphetamine 'Start Session On Wake' -bool false &&
    defaults write com.if.Amphetamine 'Restart DD Session on AC Reconnect' -bool false &&
    defaults write com.if.Amphetamine 'Allow Display Sleep' -bool true &&
    defaults write com.if.Amphetamine 'Allow Closed-Display Sleep' -bool false &&
    defaults write com.if.Amphetamine 'Enable Triggers' -bool false &&
    defaults write com.if.Amphetamine 'Trigger Data' -array
}

check "resilience.amphetamine_managed_session_policy" "Amphetamine has no generic trigger or automatic session" \
  "_amphetamine_managed_session_policy" \
  "_amphetamine_apply_managed_session_policy"

# Cross-machine sync of the managed Amphetamine preferences via
# dotfiles/data/amphetamine-prefs.json.
# When the user runs `dotfiles-amphetamine-sync export` on machine A, the synced
# JSON commits to git and `dotfiles apply` on machine B writes the same policy
# to local Amphetamine. These two checks surface the common failure modes:
#   (a) tool isn't on PATH (chmod lost, chezmoi out of sync)
#   (b) local managed policy drifted from the committed dotfiles version
#       (user reconfigured locally but didn't export, or another machine pushed
#       a newer version)
check "resilience.amphetamine_sync_tool" "dotfiles-amphetamine-sync executable" \
  "[ -x \"\$DOTFILES_DIR/bin/dotfiles-amphetamine-sync\" ]" \
  "chmod +x \"\$DOTFILES_DIR/bin/dotfiles-amphetamine-sync\""

# Soft drift check — no-op when Amphetamine isn't installed OR when the
# repo's synced JSON is empty (initial state before first export).
# Returns 0 when local == repo, non-zero when they drift.
check "resilience.amphetamine_sync_in_sync" "Amphetamine preferences match dotfiles/data/amphetamine-prefs.json" \
  "! [ -d /Applications/Amphetamine.app ] || ! [ -s \"\$DOTFILES_DIR/data/amphetamine-prefs.json\" ] || [ \"\$(jq 'keys | length' \"\$DOTFILES_DIR/data/amphetamine-prefs.json\")\" = '0' ] || \"\$DOTFILES_DIR/bin/dotfiles-amphetamine-sync\" diff >/dev/null 2>&1" \
  "echo 'Drift detected. To capture local -> dotfiles: dotfiles-amphetamine-sync export. To restore dotfiles -> local: dotfiles-amphetamine-sync apply'"

# ── Process-scoped agent keepawake (Cursor + Claude Code) ─────────────
_agent_keepawake_battery_policy_configured() {
  local plist="$HOME/Library/LaunchAgents/com.dotfiles.agent-keepawake.plist"
  [ -f "$plist" ] || return 1
  [ "$(plutil -extract EnvironmentVariables.DOTFILES_AGENT_KEEPAWAKE_BATTERY raw -o - "$plist" 2>/dev/null)" = "1" ] \
    && [ "$(plutil -extract EnvironmentVariables.DOTFILES_AGENT_KEEPAWAKE_BATTERY_MIN_PERCENT raw -o - "$plist" 2>/dev/null)" = "20" ]
}

_agent_keepawake_lid_closed_automation_healthy() {
  [ -d "$(dotfiles_agent_amphetamine_app_path)" ] || return 0
  [ ! -s "$(dotfiles_agent_amphetamine_error_file)" ] || return 1
  if dotfiles_agent_should_keepawake; then
    dotfiles_agent_amphetamine_session_active \
      && dotfiles_agent_amphetamine_closed_display_mode_enabled
    return $?
  fi
  return 0
}

_agent_keepawake_owned_amphetamine_state_is_consistent() {
  [ -f "$(dotfiles_agent_amphetamine_owner_marker)" ] || return 0
  dotfiles_agent_amphetamine_session_is_owned
}

_agent_keepawake_releases_when_idle() {
  if dotfiles_agent_should_keepawake; then
    return 0
  fi
  [ "$(dotfiles_agent_managed_caffeinate_count)" -eq 0 ] \
    && [ ! -f "$(dotfiles_agent_amphetamine_owner_marker)" ]
}

check "resilience.agent_keepawake_script" "dotfiles-agent-keepawake executable" \
  "[ -x \"\$DOTFILES_DIR/bin/dotfiles-agent-keepawake\" ]" \
  "chmod +x \"\$DOTFILES_DIR/bin/dotfiles-agent-keepawake\""

check "resilience.agent_wake_recover_script" "dotfiles-agent-wake-recover executable" \
  "[ -x \"\$DOTFILES_DIR/bin/dotfiles-agent-wake-recover\" ]" \
  "chmod +x \"\$DOTFILES_DIR/bin/dotfiles-agent-wake-recover\""

check "resilience.agent_keepawake_loaded" "agent-keepawake LaunchAgent loaded (full + Cursor or Claude Code)" \
  "[ \"\${DOTFILES_PROFILE:-full}\" != full ] || { [ ! -d /Applications/Cursor.app ] && [ ! -x \"\$HOME/.local/bin/claude\" ]; } || launchctl print \"gui/\$(id -u)/com.dotfiles.agent-keepawake\" >/dev/null 2>&1" \
  "launchctl bootstrap gui/\$UID \"\$HOME/Library/LaunchAgents/com.dotfiles.agent-keepawake.plist\" 2>/dev/null || dotfiles apply"

check "resilience.agent_keepawake_battery_policy" "agent keepawake covers AC and battery at or above 20%" \
  "[ \"\${DOTFILES_PROFILE:-full}\" != full ] || { [ ! -d /Applications/Cursor.app ] && [ ! -x \"\$HOME/.local/bin/claude\" ]; } || _agent_keepawake_battery_policy_configured" \
  "dotfiles apply && launchctl kickstart -k gui/\$UID/com.dotfiles.agent-keepawake"

check_advisory "resilience.agent_keepawake_lid_closed_automation" "Amphetamine Automation is ready for lid-closed agent work" \
  "_agent_keepawake_lid_closed_automation_healthy" \
  "In Amphetamine → Preferences → Sessions, dismiss the closed-display warning once; approve Automation for dotfiles-agent-keepawake when macOS asks; then run dotfiles-agent-keepawake"

check_advisory "resilience.agent_keepawake_owned_amphetamine_state" "Manager-owned Amphetamine session matches live qualifying agents" \
  "_agent_keepawake_owned_amphetamine_state_is_consistent" \
  "\"\$DOTFILES_DIR/bin/dotfiles-agent-keepawake\""

check_advisory "resilience.agent_keepawake_idle_release" "Manager releases its sleep protection when no eligible agent is running" \
  "_agent_keepawake_releases_when_idle" \
  "\"\$DOTFILES_DIR/bin/dotfiles-agent-keepawake\""

check "resilience.wakeup_agent_recover" '$HOME/.wakeup invokes dotfiles-agent-wake-recover on wake' \
  "[ -f \"\$HOME/.wakeup\" ] && grep -q 'dotfiles-agent-wake-recover' \"\$HOME/.wakeup\"" \
  "dotfiles apply"

check "resilience.no_legacy_cascade_caffeinate" "Legacy cascade-caffeinate LaunchAgent unloaded" \
  "! launchctl list 2>/dev/null | grep -q com.dotfiles.cascade-caffeinate" \
  "launchctl bootout gui/\$UID/com.dotfiles.cascade-caffeinate 2>/dev/null; rm -f \"\$HOME/Library/LaunchAgents/com.dotfiles.cascade-caffeinate.plist\""

check_advisory "resilience.stale_caffeinate" "No stale manager-owned caffeinate child (tracked process exited)" \
  "[ \"\$(dotfiles_agent_count_stale_caffeinate)\" -eq 0 ]" \
  "\"\$DOTFILES_DIR/bin/dotfiles-agent-keepawake\""

# ── macOS power settings ──────────────────────────────────────────────
_resilience_pmset_custom_value_is() {
  local profile="$1" key="$2" expected="$3"
  pmset -g custom 2>/dev/null | awk -v profile="$profile" -v key="$key" -v expected="$expected" '
    $0 == profile ":" { in_profile = 1; next }
    /^[^[:space:]].*:$/ { in_profile = 0 }
    in_profile && $1 == key { found = 1; ok = ($2 == expected); exit }
    END { exit(found && ok ? 0 : 1) }
  '
}

check "resilience.ac_idle_timers_normal" "AC idle timers are normal outside tracked agent work" \
  "! command -v pmset >/dev/null || { _resilience_pmset_custom_value_is 'AC Power' sleep 1 && _resilience_pmset_custom_value_is 'AC Power' disksleep 10; }" \
  "sudo pmset -c sleep 1 disksleep 10"

check_advisory "resilience.pmset_tcpkeepalive" "TCP keepalive enabled (network wake hints)" \
  "! command -v pmset >/dev/null || pmset -g | grep -q 'tcpkeepalive.*1'" \
  "sudo pmset -a tcpkeepalive 1"

# ── file descriptor limit ─────────────────────────────────────────────
# Chrome/Playwright/parallel-agent workloads can exhaust the macOS default
# ulimit (256). 4096+ is safe; we already configure 65535 in zshrc.
check "resilience.ulimit_sufficient" "ulimit -n >= 4096 (Chrome/Playwright/multi-agent)" \
  "[ \"\$(ulimit -n 2>/dev/null || echo 0)\" -ge 4096 ]" \
  "echo 'Add to ~/.zshrc: ulimit -n 8192'"

# ── Native arm64 shell (Apple Silicon) ────────────────────────────────
# On Apple Silicon Macs, the shell must run natively as arm64. If it runs
# under Rosetta (sysctl.proc_translated=1), every npx/node/playwright child
# inherits x86_64 and pays the Rosetta translation cost — measurably slower
# Playwright runs even though Chrome itself is universal binary.
#
# Root cause when this fails: Intel Homebrew installed at /usr/local/ ships
# x86_64-only bash, and /usr/local/bin appears before /opt/homebrew/bin (or
# /bin, which is universal) in PATH. When the terminal app launches bash, it
# picks the Intel one and the whole subprocess tree runs x86_64.
#
# Fix is non-trivial (PATH reorg + /opt/homebrew install) so we surface as a
# soft check on Apple Silicon only; Intel Macs trivially pass.
check_advisory "resilience.native_arm64_shell" "shell runs natively (not under Rosetta) on Apple Silicon" \
  "[ \"\$(sysctl -n hw.optional.arm64 2>/dev/null)\" != '1' ] || [ \"\$(sysctl -n sysctl.proc_translated 2>/dev/null)\" = '0' ]" \
  "Install /opt/homebrew (Apple Silicon Homebrew) and put /opt/homebrew/bin before /usr/local/bin in PATH. See: docs/troubleshooting.md#shell-running-under-rosetta"

# ── Native arm64 node toolchain (Apple Silicon) ───────────────────────
# Distinct from the shell check above: even with a native arm64 shell, fnm
# can hold an x86_64 node build if that version was installed WHILE the
# shell was translated (fnm resolves arch at install time). Then node/npm/
# npx and every node-based CLI (agent-browser, agentbrew, …) run under
# Rosetta even though the shell is native. Observed 2026-06-24: fnm
# v24.14.0 was x86_64 and wired to ~/.local/bin/node. No auto-fix —
# reinstalling node is destructive (drops global packages) — so this is
# advisory with the exact remediation in the hint.
check_advisory "resilience.node_native_arch" "active node is arm64-native on Apple Silicon" \
  "[ \"\$(sysctl -n hw.optional.arm64 2>/dev/null)\" != '1' ] || ! command -v node >/dev/null 2>&1 || [ \"\$(node -e 'process.stdout.write(process.arch)' 2>/dev/null)\" = 'arm64' ]" \
  "Active node is an x86_64 build (likely installed while the shell was under Rosetta). Reinstall native, then restore globals: FNM_ARCH=arm64 fnm uninstall <ver> && fnm install <ver>; npm i -g <your global tools>. See: docs/troubleshooting.md#shell-running-under-rosetta"

# Note: Spotlight exclusion for ~/Library/Caches/ms-playwright is already
# covered by the workflow module's spotlight.Caches check, which writes a
# .metadata_never_index marker at ~/Library/Caches/. Spotlight applies
# directory exclusions recursively per Apple's mdimport(8) manual, so the
# entire Caches tree (including ms-playwright) is de-indexed in one shot.

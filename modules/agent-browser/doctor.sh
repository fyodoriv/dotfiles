#!/bin/bash
# Doctor checks for agent-browser module

check "agent-browser.installed" "agent-browser CLI installed" \
  "command -v agent-browser" \
  ""

check "agent-browser.chrome_cdp" "dashboard Chrome launchagent installed; manual close respected" \
  "[ -f \"\$HOME/Library/LaunchAgents/com.dotfiles.agent-browser-chrome.plist\" ] || [ -f \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" ]" \
  ""

check "agent-browser.debug_chrome_cdp" "debug Chrome launchagent installed; manual close respected" \
  "[ -f \"\$HOME/Library/LaunchAgents/com.dotfiles.debug-chrome.plist\" ] || [ -f \"\$DOTFILES_DIR/launchagents/com.dotfiles.debug-chrome.plist.tmpl\" ]" \
  ""

check "agent-browser.tooling_cdp" "tooling Chrome launchagent installed; manual close respected" \
  "[ -f \"\$HOME/Library/LaunchAgents/com.dotfiles.tooling-chrome.plist\" ] || [ -f \"\$DOTFILES_DIR/launchagents/com.dotfiles.tooling-chrome.plist.tmpl\" ]" \
  ""

check "agent-browser.singleton_preflight" "singleton preflight helper installed" \
  "[ -x \"\$DOTFILES_DIR/bin/agent-browser-singleton-preflight\" ]" \
  ""

check "agent-browser.reap_strays_helper" "stray target reap helper installed" \
  "[ -x \"\$DOTFILES_DIR/bin/agent-browser-reap-strays\" ]" \
  ""

check "agent-browser.no_forwarded_launches" "launchd Chrome logs have no forwarded singleton launches" \
  "! { for log in \"\$HOME/.local/share/dotfiles/logs/agent-browser-chrome.log\" \"\$HOME/.local/share/dotfiles/logs/debug-chrome.log\" \"\$HOME/.local/share/dotfiles/logs/tooling-chrome.log\"; do [ ! -f \"\$log\" ] || grep -h 'Opening in existing browser session\\.' \"\$log\"; done; } | grep -q ." \
  "for log in \"\$HOME/.local/share/dotfiles/logs/agent-browser-chrome.log\" \"\$HOME/.local/share/dotfiles/logs/debug-chrome.log\" \"\$HOME/.local/share/dotfiles/logs/tooling-chrome.log\"; do [ ! -f \"\$log\" ] || { tmp=\"\${log}.tmp.\$\$\"; sed '/Opening in existing browser session\\./d' \"\$log\" > \"\$tmp\" && mv \"\$tmp\" \"\$log\"; }; done"

check "agent-browser.no_stray_newtab_targets" "managed Chromes expose no stray blank/newtab targets" \
  "[ ! -x \"\$DOTFILES_DIR/bin/agent-browser-reap-strays\" ] || \"\$DOTFILES_DIR/bin/agent-browser-reap-strays\" --dry-run --quiet" \
  ""

check "agent-browser.remote_debugging_process_count" "Managed Chrome process count stays at one per port" \
  "ok=1; for port in 9223 9224 9225; do count=\$(ps -axo command | awk -v port=\"\$port\" '\$0 ~ \"/MacOS/Google Chrome --remote-debugging-port[= ]\" port \"( |\$)\" {count++} END{print count+0}'); [ \"\$count\" -le 1 ] || ok=0; done; [ \"\$ok\" -eq 1 ]" \
  ""

check "agent-browser.profile_preflight_guard" "zshrc.ai-tools guards launchd-owned AGENT_BROWSER_PROFILE" \
  "grep -q 'agent-browser-singleton-preflight' \"\$DOTFILES_DIR/home/zshrc.ai-tools\"" \
  ""

check "agent-browser.legacy_launchers_safe" "legacy agent-browser launch scripts do not launch managed profiles" \
  "! { for launcher in \"\$HOME/.agent-browser/launch-chrome.sh\" \"\$HOME/.agent-browser/ensure-chrome.sh\"; do [ ! -f \"\$launcher\" ] || grep -Eh -- '--user-data-dir=.*\\.agent-browser/(chrome-profile|debug-profile|tooling-profile)|/Applications/Google Chrome\\.app' \"\$launcher\"; done; } | grep -q ." \
  ""

check "agent-browser.profile_dir" "agent-browser Chrome profile exists" \
  "[ -d \"\$HOME/.agent-browser/chrome-profile\" ]" \
  "mkdir -p \"\$HOME/.agent-browser/chrome-profile\""

# Each persistent Chrome should have a distinct Material You theme color
# applied to its profile, so the human can tell them apart at a glance.
# Color encoding is signed-int32 of ARGB uint32 (alpha 0xFF). The fix path
# (`bin/dotfiles-set-persistent-chrome-themes`) is idempotent and a no-op
# when the profile is already themed correctly.
check "agent-browser.dashboard_theme" "dashboard Chrome themed BLUE (port 9223)" \
  "jq -e '.browser.theme.user_color2 == -16746043' \"\$HOME/.agent-browser/chrome-profile/Default/Preferences\" >/dev/null 2>&1" \
  "\"\$DOTFILES_DIR/bin/dotfiles-set-persistent-chrome-themes\" 9223"

check "agent-browser.debug_chrome_theme" "debug Chrome themed ORANGE (port 9224)" \
  "jq -e '.browser.theme.user_color2 == -355840' \"\$HOME/.agent-browser/debug-profile/Default/Preferences\" >/dev/null 2>&1" \
  "\"\$DOTFILES_DIR/bin/dotfiles-set-persistent-chrome-themes\" 9224"

check "agent-browser.tooling_theme" "tooling Chrome themed PURPLE (port 9225)" \
  "jq -e '.browser.theme.user_color2 == -6543440' \"\$HOME/.agent-browser/tooling-profile/Default/Preferences\" >/dev/null 2>&1" \
  "\"\$DOTFILES_DIR/bin/dotfiles-set-persistent-chrome-themes\" 9225"

check "agent-browser.spotlight_excluded" "agent-browser dir excluded from Spotlight" \
  "[ -f \"\$HOME/.agent-browser/.metadata_never_index\" ]" \
  "touch \"\$HOME/.agent-browser/.metadata_never_index\" 2>/dev/null"

# Search both zshrc and zshrc.ai-tools so the check matches reality —
# AGENT_BROWSER_* exports live in zshrc.ai-tools (opt-in via use_ai_tools),
# not in the always-loaded zshrc.
check "agent-browser.idle_timeout" "AGENT_BROWSER_IDLE_TIMEOUT_MS set for daemon keep-alive" \
  "grep -q 'AGENT_BROWSER_IDLE_TIMEOUT_MS' \"\$DOTFILES_DIR/home/zshrc\" \"\$DOTFILES_DIR/home/zshrc.ai-tools\" 2>/dev/null" \
  ""

check "agent-browser.env_timeout" "AGENT_BROWSER_DEFAULT_TIMEOUT configured" \
  "grep -q 'AGENT_BROWSER_DEFAULT_TIMEOUT' \"\$DOTFILES_DIR/home/zshrc\" \"\$DOTFILES_DIR/home/zshrc.ai-tools\" 2>/dev/null" \
  ""

check "agent-browser.focus_restore_helper" "focus-restore helper installed for agent-browser wrapper" \
  "[ -x \"\$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome\" ]" \
  ""

check "agent-browser.focus_restore_wired" "zshrc.ai-tools restores focus after agent-browser when Chrome steals it" \
  "grep -q 'dotfiles-restore-focus-after-chrome' \"\$DOTFILES_DIR/home/zshrc.ai-tools\"" \
  ""

check "agent-browser.launchagent_no_startup_window" "managed Chromes use --no-startup-window at login" \
  "grep -q -- '--no-startup-window' \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.debug-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.tooling-chrome.plist.tmpl\"" \
  ""

check "agent-browser.restore_no_activate" "focus-restore helper never osascript-activates or hides Chrome (no Space switch)" \
  "! grep -vE '^[[:space:]]*#' \"\$DOTFILES_DIR/bin/dotfiles-restore-focus-after-chrome\" | grep -qE 'to activate|set visible to false'" \
  ""

# shellcheck source=../../lib/focus-steal-audit.sh
source "$DOTFILES_DIR/lib/focus-steal-audit.sh"

check "focus.no_steal_open_flags" "open -a in bin/lib/launchagents uses -g, --gj, or --background only" \
  "[ -z \"\$(focus_steal_open_a_violations)\" ]" \
  "focus_steal_open_a_violations | head -5"

check "focus.no_osascript_activate" "no osascript 'to activate' in bin/lib/launchagents/macos-apps.sh" \
  "[ -z \"\$(focus_steal_activate_violations)\" ]" \
  "focus_steal_activate_violations | head -5"

check "agent-browser.launchagent_headless" "managed Chromes use --headless=new (no GUI focus steal)" \
  "ok=1; for plist in \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.debug-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.tooling-chrome.plist.tmpl\"; do grep -q -- '--headless=new' \"\$plist\" || ok=0; done; [ \"\$ok\" -eq 1 ]" \
  ""

check "agent-browser.launchagent_no_offscreen_position" "managed Chromes omit --window-position (prevents flash-quit loop)" \
  "! grep -q -- '--window-position=' \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.debug-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.tooling-chrome.plist.tmpl\"" \
  ""

check "agent-browser.launchagent_no_keepalive" "managed Chromes do not KeepAlive-reopen during logout/shutdown" \
  "ok=1; for plist in \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.debug-chrome.plist.tmpl\" \"\$DOTFILES_DIR/launchagents/com.dotfiles.tooling-chrome.plist.tmpl\"; do grep -A1 '<key>KeepAlive</key>' \"\$plist\" | grep -q '<false/>' || ok=0; done; [ \"\$ok\" -eq 1 ]" \
  ""

check "agent-browser.cdp_wrapper" "agent-browser shell wrapper auto-uses --cdp 9223" \
  "grep -q 'agent-browser --cdp 9223' \"\$DOTFILES_DIR/home/zshrc.ai-tools\" && grep -q '_DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION' \"\$DOTFILES_DIR/home/zshrc.ai-tools\"" \
  ""

check "agent-browser.launchagent_runatload" "agent-browser-chrome launchagent has RunAtLoad=true" \
  "grep -A1 'RunAtLoad' \"\$DOTFILES_DIR/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl\" | grep -q '<true/>'" \
  ""

# Per-agent daemon identity: in an agent context the shell should have
# assigned AGENT_BROWSER_SESSION to a non-"default" value (see
# home/zshrc.ai-tools). The wrapper attaches dotfiles-assigned agent
# sessions to managed CDP by default, while the session name keeps daemon
# state distinct and preserves the explicit-isolation escape hatch.
#
# Outside an agent context this check is a no-op — operators may use the
# "default" session intentionally to get the --cdp 9223 fast path.
check "agent-browser.agent_session_isolation" "AGENT_BROWSER_SESSION set when in agent context" \
  "[ -z \"\${DEVIN_SESSION_ID:-\${CLAUDE_CODE_SSE_PORT:-\${CURSOR_AGENT:-\${WINDSURF_AGENT:-\${CODEX_AGENT:-}}}}}\" ] || { [ -n \"\${AGENT_BROWSER_SESSION:-}\" ] && [ \"\${AGENT_BROWSER_SESSION:-default}\" != default ]; }" \
  ""

# Source-of-truth check: lib/agent-browser-session-env.sh must stay wired from
# env.sh and zshrc.ai-tools. Catches accidental removal during refactors.
check "agent-browser.agent_session_wired" "agent-browser session env wired for agent contexts" \
  "[ -f \"\$DOTFILES_DIR/lib/agent-browser-session-env.sh\" ] && grep -q 'AGENT_BROWSER_SESSION=\"devin-' \"\$DOTFILES_DIR/lib/agent-browser-session-env.sh\" && grep -q 'AGENT_BROWSER_SESSION=\"claude-' \"\$DOTFILES_DIR/lib/agent-browser-session-env.sh\" && grep -q 'agent-browser-session-env.sh' \"\$DOTFILES_DIR/home/zshrc.ai-tools\" \"\$DOTFILES_DIR/dot_config/dotfiles/env.sh.tmpl\" 2>/dev/null" \
  ""

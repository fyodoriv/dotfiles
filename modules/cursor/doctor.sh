#!/bin/bash
# Doctor checks for the cursor module.
# Manages Cursor user-level settings, keybindings, tasks, and recommended extensions.
#
# Source of truth: $DOTFILES_DIR/cursor/
#   - settings.json     → symlinked into User/settings.json
#   - keybindings.json  → symlinked into User/keybindings.json
#   - tasks.json        → symlinked into User/tasks.json
#   - extensions.txt    → one extension id per line; doctor installs missing
#
# Ownership boundary:
#   - dotfiles owns ~/Library/Application Support/Cursor/User/{settings,keybindings,tasks}.json
#     AND installed extensions (one-directional: doctor adds, never removes)
#   - agentbrew owns ~/.cursor/ (rules, skills, mcp, hooks)
#
# Per-machine override:
#   $CURSOR_LOCAL_DIR/{settings,keybindings,tasks}.override.json5 — symlinks the
#   override file instead of the dotfiles base.

# use_cursor=false (chezmoi data) means this machine has no Cursor.
if [ "${USE_CURSOR:-true}" = "false" ]; then
  # shellcheck disable=SC2317  # return when sourced; exit when executed directly
  return 0 2>/dev/null || exit 0
fi

# shellcheck source=../../lib/dotfiles-arch.sh
source "$DOTFILES_DIR/lib/dotfiles-arch.sh"

_CR_LOCAL="${CURSOR_LOCAL_DIR:-$HOME/.local/share/dotfiles-cursor}"
_CR_USER_DIR="$HOME/Library/Application Support/Cursor/User"
_CR_BIN="$HOME/.local/bin/cursor"
_CR_APP="/Applications/Cursor.app"
if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
  _CR_OVERLAY_ROOT="$EXTRA_OVERLAY_ROOT"
elif command -v chezmoi >/dev/null 2>&1; then
  _CR_OVERLAY_ROOT="$(chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || echo "")"
else
  _CR_OVERLAY_ROOT=""
fi
_CR_EXT_LISTS=("$DOTFILES_DIR/cursor/extensions.txt")
[ -n "$_CR_OVERLAY_ROOT" ] && [ -f "$_CR_OVERLAY_ROOT/cursor/extensions.txt" ] && _CR_EXT_LISTS+=("$_CR_OVERLAY_ROOT/cursor/extensions.txt")

# ── Cursor installed ──────────────────────────────────────────────────────
check "cursor.installed" \
  "Cursor.app installed" \
  "[ -d '$_CR_APP' ]" \
  ""

check "cursor.cli" \
  "Cursor CLI available at ~/.local/bin/cursor" \
  "[ -x '$_CR_BIN' ]" \
  ""

if dotfiles_is_apple_silicon; then
  check "cursor.native_arch" \
    "Cursor.app binary includes arm64 (not Intel-only) on Apple Silicon" \
    "[ ! -d '$_CR_APP' ] || dotfiles_app_binary_includes_arm64 '$_CR_APP'" \
    "brew reinstall --cask cursor  # quit Cursor, reopen; or download arm64 build from cursor.com"
fi

# ── Settings.json (with optional per-machine override) ────────────────────
_cr_settings_source="$DOTFILES_DIR/cursor/settings.json"
_cr_generated_settings="$_CR_LOCAL/settings.generated.json"
_cr_overlay_settings="$_CR_OVERLAY_ROOT/cursor/settings.json"
if [ -f "$DOTFILES_DIR/cursor/settings.json" ]; then
  _cr_settings_source="$_cr_generated_settings"
  mkdir -p "$_CR_LOCAL"
  python3 - "$DOTFILES_DIR/cursor/settings.json" "$_cr_settings_source" "$_cr_overlay_settings" <<'PY'
import json
import os
import sys

base_path, output_path, overlay_path = sys.argv[1:]

def jsonc_to_json(text):
    out = []
    in_string = False
    in_line_comment = False
    in_block_comment = False
    escape = False
    i = 0
    while i < len(text):
        char = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""
        if in_line_comment:
            if char == "\n":
                in_line_comment = False
                out.append(char)
            i += 1
            continue
        if in_block_comment:
            if char == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                if char == "\n":
                    out.append(char)
                i += 1
            continue
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            i += 1
            continue
        if char == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if char == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        out.append(char)
        i += 1

    text = "".join(out)
    out = []
    in_string = False
    escape = False
    i = 0
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            i += 1
            continue
        if char == '"':
            in_string = True
            out.append(char)
            i += 1
            continue
        if char == ",":
            j = i + 1
            while j < len(text) and text[j].isspace():
                j += 1
            if j < len(text) and text[j] in "}]":
                i += 1
                continue
        out.append(char)
        i += 1
    return "".join(out)

def merge(left, right):
    if isinstance(left, dict) and isinstance(right, dict):
        merged = dict(left)
        for key, value in right.items():
            merged[key] = merge(merged[key], value) if key in merged else value
        return merged
    return right

def load(path):
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            return json.loads(jsonc_to_json(handle.read()))
    except json.JSONDecodeError:
        return {}

merged = load(base_path)
if os.path.exists(output_path):
    current = load(output_path)
    for key in ("mcpServers", "mcp"):
        if key in current:
            merged[key] = merge(merged.get(key, {}), current[key])
if os.path.exists(overlay_path):
    merged = merge(merged, load(overlay_path))
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(merged, handle, indent=2)
    handle.write("\n")
PY
fi
[ -f "$_CR_LOCAL/settings.override.json5" ] && _cr_settings_source="$_CR_LOCAL/settings.override.json5"
check_symlink "cursor.symlink.settings" \
  "$_cr_settings_source" \
  "$_CR_USER_DIR/settings.json"

check "cursor.external_browser_chromework" \
  "Cursor leaves external browser unset so macOS default routes through ChromeWork" \
  "python3 - \"$_cr_generated_settings\" <<'PY'
import json
import sys

with open(sys.argv[1], encoding=\"utf-8\") as handle:
    settings = json.load(handle)
browser = settings.get(\"workbench.externalBrowser\")
assert browser in (None, \"\"), (
    \"workbench.externalBrowser must be unset; Cursor does not expand \"
    f\"environment variables in settings: {browser!r}\"
)
PY" \
  "chezmoi apply  # leave cursor/settings.json workbench.externalBrowser unset"

check "cursor.terminal_path_dotfiles" \
  "Cursor terminal.integrated.env.osx prepends dotfiles/bin to PATH" \
  "python3 - \"$_cr_generated_settings\" <<'PY'
import json
import sys

settings = json.load(open(sys.argv[1], encoding='utf-8'))
env = settings.get('terminal.integrated.env.osx') or {}
path = env.get('PATH', '')
assert 'dotfiles/bin' in path, f'missing dotfiles/bin in PATH: {path!r}'
assert ':\${env:PATH}' in path or path.endswith('\${env:PATH}'), f'PATH must append env PATH: {path!r}'
PY" \
  "chezmoi apply  # cursor/settings.json terminal.integrated.env.osx PATH"

_hooks_json="$HOME/.cursor/hooks.json"
_hooks_dir="$HOME/.config/dotfiles/hooks"
check "cursor.agent_hooks_installed" \
  "Cursor agent-hooks linked in ~/.config/dotfiles/hooks" \
  "[ -x '$_hooks_dir/prepend-endpoint-path.sh' ] && [ -x '$_hooks_dir/block-dangerous-git.sh' ]" \
  "chezmoi apply  # run_after_cursor-agent-hooks.sh; agentbrew sync"

if [ -f "$_hooks_json" ]; then
  check "cursor.agent_shell_endpoint_path_hook" \
    "Cursor preToolUse hook prepends dotfiles/bin for Shell tool (agent sandbox PATH)" \
    "python3 - \"$_hooks_json\" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding='utf-8'))
items = hooks.get('hooks', {}).get('preToolUse', [])
found = any(
    'prepend-endpoint-path' in (item.get('command') or '')
    and item.get('matcher') in ('Shell', 'Bash', 'Task', '*', None)
    for item in items
)
assert found, 'missing prepend-endpoint-path preToolUse hook for Shell/Bash/Task'
PY" \
    "chezmoi apply  # Agentfile hooks + agentbrew sync"

  check "cursor.agent_task_endpoint_path_hook" \
    "Cursor preToolUse prepend-endpoint-path hook includes Task matcher (subagent shells)" \
    "python3 - \"$_hooks_json\" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding='utf-8'))
items = hooks.get('hooks', {}).get('preToolUse', [])
found = any(
    'prepend-endpoint-path' in (item.get('command') or '')
    and item.get('matcher') == 'Task'
    for item in items
)
assert found, 'missing prepend-endpoint-path preToolUse hook for Task'
PY" \
    "chezmoi apply  # Agentfile Task matcher + agentbrew sync"

  check "cursor.hooks_endpoint_bootstrap_installed" \
    "Endpoint PATH bootstrap hooks linked in ~/.config/dotfiles/hooks" \
    "[ -x '$_hooks_dir/bootstrap-endpoint-path.sh' ] && [ -x '$_hooks_dir/with-endpoint-path.sh' ]" \
    "chezmoi apply  # run_after_cursor-agent-hooks.sh"

  check "cursor.codeassist_audit_hooks_jq_path" \
    "Codeassist audit hooks wrapped with with-endpoint-path (sandbox jq endpoint agent fix)" \
    "python3 - \"$_hooks_json\" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding='utf-8'))
wrapper = 'with-endpoint-path'
audit_events = ('afterFileEdit', 'afterAgentResponse', 'afterMCPExecution')
for event in audit_events:
    for item in hooks.get('hooks', {}).get(event, []):
        cmd = item.get('command') or ''
        if 'audit-logger' in cmd:
            assert wrapper in cmd, f'{event} audit-logger missing {wrapper} wrapper: {cmd!r}'
PY" \
    "chezmoi apply  # run_after_cursor-hooks-endpoint-wrap.sh after agentbrew sync"

  check "cursor.codeassist_stop_hooks_wrapped" \
    "Codeassist stop hooks wrapped with with-endpoint-path" \
    "python3 - \"$_hooks_json\" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding='utf-8'))
wrapper = 'with-endpoint-path'
for item in hooks.get('hooks', {}).get('stop', []):
    cmd = item.get('command') or ''
    if 'hooks-scripts/' in cmd:
        assert wrapper in cmd, f'stop hook missing wrapper: {cmd!r}'
PY" \
    "chezmoi apply  # run_after_cursor-hooks-endpoint-wrap.sh"

  check "cursor.hooks_no_duplicates" \
    "Cursor hooks.json has no duplicate hook entries" \
    "python3 - \"$_hooks_json\" <<'PY'
import json
import sys

hooks = json.load(open(sys.argv[1], encoding='utf-8'))
for event, items in hooks.get('hooks', {}).items():
    keys = [(i.get('matcher'), i.get('timeout'), i.get('command')) for i in items]
    assert len(keys) == len(set(keys)), f'{event} has duplicate hook entries'
PY" \
    "chezmoi apply  # run_after_cursor-hooks-endpoint-wrap.sh"
fi
unset _hooks_json _hooks_dir

# ── Keybindings.json (with optional per-machine override) ─────────────────
_cr_keybindings_source="$DOTFILES_DIR/cursor/keybindings.json"
[ -f "$_CR_LOCAL/keybindings.override.json5" ] && _cr_keybindings_source="$_CR_LOCAL/keybindings.override.json5"
check_symlink "cursor.symlink.keybindings" \
  "$_cr_keybindings_source" \
  "$_CR_USER_DIR/keybindings.json"

# ── Tasks.json (with optional per-machine override) ────────────────────────
_cr_tasks_source="$DOTFILES_DIR/cursor/tasks.json"
[ -f "$_CR_LOCAL/tasks.override.json5" ] && _cr_tasks_source="$_CR_LOCAL/tasks.override.json5"
check_symlink "cursor.symlink.tasks" \
  "$_cr_tasks_source" \
  "$_CR_USER_DIR/tasks.json"

# ── Stale agent sandbox shells (vitest / tail -f / watch:pr) ─────────
# shellcheck source=../../lib/heal-stuck-agents.sh
source "$DOTFILES_DIR/lib/heal-stuck-agents.sh"

check "cursor.stale_agent_shells" \
  "No stale Cursor agent sandbox shells (vitest/tail -f/watch:pr >30 min)" \
  "[ \"\$(dotfiles_heal_count_stale_agent_shells)\" -eq 0 ]" \
  "'$DOTFILES_DIR/bin/dotfiles-heal-stuck-agents' --fix --quiet"

check "cursor.runaway_agent_helpers" \
  "No runaway Cursor helper crawls (>90% CPU for >60 sec)" \
  "[ \"\$(dotfiles_heal_count_runaway_agent_helpers)\" -eq 0 ]" \
  "'$DOTFILES_DIR/bin/dotfiles-heal-stuck-agents' --fix --quiet"

# Skip app-dependent checks if Cursor isn't installed.
[ -d "$_CR_APP" ] || return 0

check "cursor.model_parity" \
  "Cursor default model matches Claude Code" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-parity.sh' --check-model" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-parity.sh'"

check "cursor.agent_settings_parity" \
  "Cursor agent surfaces match editor settings (vim, fonts, glass keybindings)" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-parity.sh' --check-settings" \
  "bash '$DOTFILES_DIR/.chezmoiscripts/run_after_cursor-agent-parity.sh'"

# Vitest extension floods Output and spawns processes when it discovers
# vitest.config.ts in doc mirrors / worktrees without node_modules/vitest.
check_advisory "cursor.vitest_discovery_guard" \
  "Vitest extension config discovery excludes mirror/worktree/doc paths" \
  "python3 - \"$_cr_generated_settings\" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, encoding=\"utf-8\") as handle:
    settings = json.load(handle)
exclude = settings.get(\"vitest.configSearchPatternExclude\", \"\")
required = (\"docs\", \"worktrees\", \"scrub-tmp\", \"_inventory\", \"caliber-research\")
missing = [part for part in required if part not in exclude]
if missing:
    raise SystemExit(f\"missing exclude markers: {missing}\")
if settings.get(\"vitest.logLevel\") != \"info\":
    raise SystemExit(\"vitest.logLevel should be info\")
PY" \
  "Re-run dotfiles doctor --module cursor --fix to regenerate Cursor settings"

# ── Font shared with jetbrains module (advisory) ──────────────────────────
check_advisory "cursor.font.jetbrains_mono_nerd" \
  "JetBrainsMono Nerd Font available (shared with jetbrains module)" \
  "fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'" \
  "Install via Brewfile: 'brew install --cask font-jetbrains-mono-nerd-font' (already in dotfiles Brewfile)"

# ── Extensions ────────────────────────────────────────────────────────────
_cr_desired_extensions() {
  local list
  for list in "${_CR_EXT_LISTS[@]}"; do
    [ -f "$list" ] || continue
    grep -v '^#' "$list" | grep -v '^$' | tr -d ' \t'
  done | sort -u
}

_cr_installed_extensions() {
  [ -x "$_CR_BIN" ] || return 0
  "$_CR_BIN" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

_cr_extension_installed() {
  local ext="$1"
  local ext_lc
  ext_lc="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  _cr_installed_extensions | grep -Fxq "$ext_lc"
}

# Corporate-CA bundle pattern (also used by the vscode module): Cursor's bundled
# Electron Node doesn't honour the macOS keychain, so we materialise a PEM
# from System.keychain + SystemRootCertificates.keychain and pass it via
# NODE_EXTRA_CA_CERTS for `cursor --install-extension`. Refreshed monthly.
_CR_CA_BUNDLE="$_CR_LOCAL/ca-bundle.pem"
if [ ! -f "$_CR_CA_BUNDLE" ] || [ -n "$(find "$_CR_CA_BUNDLE" -mtime +30 2>/dev/null)" ]; then
  mkdir -p "$_CR_LOCAL"
  if {
    security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain 2>/dev/null
  } > "$_CR_CA_BUNDLE.tmp" 2>/dev/null; then
    mv "$_CR_CA_BUNDLE.tmp" "$_CR_CA_BUNDLE"
  else
    rm -f "$_CR_CA_BUNDLE.tmp"
  fi
fi
if [ -s "$_CR_CA_BUNDLE" ]; then
  _CR_INSTALL_ENV="NODE_EXTRA_CA_CERTS='$_CR_CA_BUNDLE'"
else
  _CR_INSTALL_ENV=""
fi

export FIX_TIMEOUT="${FIX_TIMEOUT:-180}"

_cr_ext_tmp="$(mktemp)"
_cr_desired_extensions > "$_cr_ext_tmp" 2>/dev/null || true

if [ -s "$_cr_ext_tmp" ]; then
  while IFS= read -r _cr_ext; do
    [ -z "$_cr_ext" ] && continue
    _cr_slug="$(printf '%s' "$_cr_ext" | tr './' '__')"
    check "cursor.extension.$_cr_slug" \
      "$_cr_ext installed" \
      "_cr_extension_installed '$_cr_ext'" \
      "$_CR_INSTALL_ENV '$_CR_BIN' --install-extension '$_cr_ext' --force"
  done < "$_cr_ext_tmp"
fi
rm -f "$_cr_ext_tmp"

# ── agentbrew presence (advisory) ─────────────────────────────────────────
check_advisory "cursor.agentbrew_present" \
  "Cursor agent-config dir present (~/.cursor — agentbrew-managed)" \
  "[ -d '$HOME/.cursor' ]" \
  "Run 'dotfiles apply' or 'agentbrew sync --agentfile ~/apps/tooling/dotfiles/Agentfile.yaml' to materialise rules/skills/MCP."

# When memory is registered, verify the same full discovery contract that the
# login wrapper uses. This is advisory because Cursor can still open degraded
# when the bounded startup wait expires; it must never restart Cursor itself.
_cr_memory_service_registered() {
  [ -f "$HOME/.config/agentbrew/state.yaml" ] || return 1
  grep -q 'name: memory' "$HOME/.config/agentbrew/state.yaml" &&
    grep -q 'http://127.0.0.1:18765/mcp' "$HOME/.config/agentbrew/state.yaml"
}

if command -v agentbrew >/dev/null 2>&1 && _cr_memory_service_registered; then
  # shellcheck source=../../lib/agentbrew-memory-readiness.sh
  source "$DOTFILES_DIR/lib/agentbrew-memory-readiness.sh"
  check_advisory "cursor.memory_mcp_ready" \
    "Cursor memory MCP passes AgentBrew full discovery gate (initialize + tools/list)" \
    "dotfiles_agentbrew_memory_doctor_ready" \
    "agentbrew memory fix; then manually reload or fully restart Cursor"
fi

# ── Login startup (macos-apps.sh + LaunchAgent) ───────────────────────────
check "cursor.at_login_launchagent" \
  "cursor-at-login verifies full AgentBrew memory discovery before open -g -a Cursor" \
  "[ -x \"\$DOTFILES_DIR/bin/cursor-at-login\" ] && grep -q 'bin/cursor-at-login</string>' \"\$DOTFILES_DIR/launchagents/com.dotfiles.cursor-at-login.plist.tmpl\" && grep -q 'CURSOR_LOGIN_WAIT_FOR_MEMORY' \"\$DOTFILES_DIR/launchagents/com.dotfiles.cursor-at-login.plist.tmpl\" && grep -q 'memory doctor' \"\$DOTFILES_DIR/bin/cursor-at-login\" && grep -q 'memory fix' \"\$DOTFILES_DIR/bin/cursor-at-login\" && grep -q 'exec \"\$open_bin\" -g -a Cursor' \"\$DOTFILES_DIR/bin/cursor-at-login\"" \
  "agentbrew memory fix && chezmoi apply"

if [ -d "$_CR_APP" ]; then
  check "cursor.at_login_loaded" \
    "com.dotfiles.cursor-at-login LaunchAgent registered" \
    "launchctl print \"gui/\$(id -u)/com.dotfiles.cursor-at-login\" >/dev/null 2>&1" \
    "launchctl bootstrap gui/\$(id -u) \"\$HOME/Library/LaunchAgents/com.dotfiles.cursor-at-login.plist\" 2>/dev/null || launchctl load \"\$HOME/Library/LaunchAgents/com.dotfiles.cursor-at-login.plist\" 2>/dev/null"

  check "cursor.no_webstorm_login_item" \
    "WebStorm not in macOS Login Items (Cursor replaces it at login)" \
    "! osascript -e 'tell application \"System Events\" to get the name of every login item' 2>/dev/null | grep -q WebStorm" \
    "osascript -e 'tell application \"System Events\" to delete login item \"WebStorm\"' 2>/dev/null || chezmoi apply  # macos-apps.sh removes legacy login item"
fi

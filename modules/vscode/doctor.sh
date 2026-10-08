#!/bin/bash
# Doctor checks for the vscode module.
# Manages VS Code user-level settings + keybindings + recommended extensions.
#
# Source of truth: $DOTFILES_DIR/vscode/
#   - settings.json     → symlinked into User/settings.json
#   - keybindings.json  → symlinked into User/keybindings.json
#   - extensions.txt    → one extension id per line; doctor installs missing
#
# This module mirrors modules/cursor/doctor.sh.

_VC_LOCAL="${VSCODE_LOCAL_DIR:-$HOME/.local/share/dotfiles-vscode}"
_VC_USER_DIR="$HOME/Library/Application Support/Code/User"
_VC_APP="/Applications/Visual Studio Code.app"
# The app bundle ships the CLI; use it when `code` is not on PATH.
_VC_BIN="$(command -v code 2>/dev/null || true)"
if [ -z "$_VC_BIN" ] && [ -x "$_VC_APP/Contents/Resources/app/bin/code" ]; then
  _VC_BIN="$_VC_APP/Contents/Resources/app/bin/code"
fi
: "${_VC_BIN:=/usr/local/bin/code}"
if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
  _VC_OVERLAY_ROOT="$EXTRA_OVERLAY_ROOT"
elif command -v chezmoi >/dev/null 2>&1; then
  _VC_OVERLAY_ROOT="$(chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || echo "")"
else
  _VC_OVERLAY_ROOT=""
fi
_VC_EXT_LISTS=("$DOTFILES_DIR/vscode/extensions.txt")
[ -n "$_VC_OVERLAY_ROOT" ] && [ -f "$_VC_OVERLAY_ROOT/vscode/extensions.txt" ] && _VC_EXT_LISTS+=("$_VC_OVERLAY_ROOT/vscode/extensions.txt")

# ── VS Code installed ─────────────────────────────────────────────────────
check "vscode.installed" \
  "VS Code installed" \
  "[ -d '$_VC_APP' ]" \
  ""

check "vscode.cli" \
  "code CLI available" \
  "[ -x '$_VC_BIN' ]" \
  ""

# ── Settings.json (with optional per-machine override) ────────────────────
_vc_settings_source="$DOTFILES_DIR/vscode/settings.json"
_vc_generated_settings="$_VC_LOCAL/settings.generated.json"
_vc_overlay_settings="$_VC_OVERLAY_ROOT/vscode/settings.json"
if [ -f "$DOTFILES_DIR/vscode/settings.json" ]; then
  _vc_settings_source="$_vc_generated_settings"
  mkdir -p "$_VC_LOCAL"
  python3 - "$DOTFILES_DIR/vscode/settings.json" "$_vc_settings_source" "$_vc_overlay_settings" <<'PY'
import json
import os
import sys

base_path, output_path, overlay_path = sys.argv[1:]

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
            return json.load(handle)
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
[ -f "$_VC_LOCAL/settings.override.json5" ] && _vc_settings_source="$_VC_LOCAL/settings.override.json5"
check_symlink "vscode.symlink.settings" \
  "$_vc_settings_source" \
  "$_VC_USER_DIR/settings.json"

# ── Keybindings.json (with optional per-machine override) ─────────────────
_vc_keybindings_source="$DOTFILES_DIR/vscode/keybindings.json"
[ -f "$_VC_LOCAL/keybindings.override.json5" ] && _vc_keybindings_source="$_VC_LOCAL/keybindings.override.json5"
check_symlink "vscode.symlink.keybindings" \
  "$_vc_keybindings_source" \
  "$_VC_USER_DIR/keybindings.json"

# Skip app-dependent checks if VS Code isn't installed.
[ -d "$_VC_APP" ] || return 0

# ── Font shared with jetbrains module (advisory) ──────────────────────────
check_advisory "vscode.font.jetbrains_mono_nerd" \
  "JetBrainsMono Nerd Font available (shared with jetbrains module)" \
  "fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'" \
  "Install via Brewfile: 'brew install --cask font-jetbrains-mono-nerd-font' (already in dotfiles Brewfile)"

# ── Extensions ────────────────────────────────────────────────────────────
_vc_desired_extensions() {
  local list
  for list in "${_VC_EXT_LISTS[@]}"; do
    [ -f "$list" ] || continue
    grep -v '^#' "$list" | grep -v '^$' | tr -d ' \t'
  done | sort -u
}

_vc_installed_extensions() {
  [ -x "$_VC_BIN" ] || return 0
  "$_VC_BIN" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

_vc_extension_installed() {
  local ext="$1"
  local ext_lc
  ext_lc="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  _vc_installed_extensions | grep -Fxq "$ext_lc"
}

# Corporate-CA bundle (same pattern as the cursor doctor).
_VC_CA_BUNDLE="$_VC_LOCAL/ca-bundle.pem"
if [ ! -f "$_VC_CA_BUNDLE" ] || [ -n "$(find "$_VC_CA_BUNDLE" -mtime +30 2>/dev/null)" ]; then
  mkdir -p "$_VC_LOCAL"
  if {
    security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain 2>/dev/null
  } > "$_VC_CA_BUNDLE.tmp" 2>/dev/null; then
    mv "$_VC_CA_BUNDLE.tmp" "$_VC_CA_BUNDLE"
  else
    rm -f "$_VC_CA_BUNDLE.tmp"
  fi
fi
if [ -s "$_VC_CA_BUNDLE" ]; then
  _VC_INSTALL_ENV="NODE_EXTRA_CA_CERTS='$_VC_CA_BUNDLE'"
else
  _VC_INSTALL_ENV=""
fi

export FIX_TIMEOUT="${FIX_TIMEOUT:-180}"

_vc_ext_tmp="$(mktemp)"
_vc_desired_extensions > "$_vc_ext_tmp" 2>/dev/null || true

if [ -s "$_vc_ext_tmp" ]; then
  while IFS= read -r _vc_ext; do
    [ -z "$_vc_ext" ] && continue
    _vc_slug="$(printf '%s' "$_vc_ext" | tr './' '__')"
    check "vscode.extension.$_vc_slug" \
      "$_vc_ext installed" \
      "_vc_extension_installed '$_vc_ext'" \
      "$_VC_INSTALL_ENV '$_VC_BIN' --install-extension '$_vc_ext' --force"
  done < "$_vc_ext_tmp"
fi
rm -f "$_vc_ext_tmp"

#!/bin/bash
# Doctor checks for the windsurf module.
# Manages Windsurf user-level settings + keybindings + recommended extensions.
#
# Source of truth: $DOTFILES_DIR/windsurf/
#   - settings.json     → symlinked into User/settings.json
#   - keybindings.json  → symlinked into User/keybindings.json
#   - extensions.txt    → one extension id per line; doctor installs missing
#
# Ownership boundary (see windsurf/README.md):
#   - dotfiles owns ~/Library/Application Support/Windsurf/User/{settings,keybindings}.json
#     AND installed extensions (one-directional: doctor adds, never removes)
#   - agentbrew owns ~/.codeium/windsurf/ (Cascade, MCP, skills, rules)
#
# Per-machine override:
#   $WINDSURF_LOCAL_DIR/{settings,keybindings}.override.json5 — symlinks the
#   override file instead of the dotfiles base. Useful for one-machine font
#   size, tsserver heap, or experimental keybinds without touching git.

_WS_LOCAL="${WINDSURF_LOCAL_DIR:-$HOME/.local/share/dotfiles-windsurf}"
_WS_USER_DIR="$HOME/Library/Application Support/Windsurf/User"
_WS_BIN="$HOME/.codeium/windsurf/bin/windsurf"
_WS_APP="/Applications/Windsurf.app"
if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
  _WS_OVERLAY_ROOT="$EXTRA_OVERLAY_ROOT"
elif command -v chezmoi >/dev/null 2>&1; then
  _WS_OVERLAY_ROOT="$(chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || echo "")"
else
  _WS_OVERLAY_ROOT=""
fi
_WS_EXT_LISTS=("$DOTFILES_DIR/windsurf/extensions.txt")
[ -n "$_WS_OVERLAY_ROOT" ] && [ -f "$_WS_OVERLAY_ROOT/windsurf/extensions.txt" ] && _WS_EXT_LISTS+=("$_WS_OVERLAY_ROOT/windsurf/extensions.txt")

# ── Windsurf installed ─────────────────────────────────────────────────────
check "windsurf.installed" \
  "Windsurf.app installed" \
  "[ -d '$_WS_APP' ]" \
  ""

check "windsurf.cli" \
  "Windsurf CLI available at ~/.codeium/windsurf/bin/windsurf" \
  "[ -x '$_WS_BIN' ]" \
  ""

# ── Settings.json (with optional per-machine override) ─────────────────────
_ws_settings_source="$DOTFILES_DIR/windsurf/settings.json"
_ws_generated_settings="$_WS_LOCAL/settings.generated.json"
_ws_overlay_settings="$_WS_OVERLAY_ROOT/windsurf/settings.json"
if [ -f "$DOTFILES_DIR/windsurf/settings.json" ]; then
  _ws_settings_source="$_ws_generated_settings"
  mkdir -p "$_WS_LOCAL"
  python3 - "$DOTFILES_DIR/windsurf/settings.json" "$_ws_settings_source" "$_ws_overlay_settings" <<'PY'
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
[ -f "$_WS_LOCAL/settings.override.json5" ] && _ws_settings_source="$_WS_LOCAL/settings.override.json5"
check_symlink "windsurf.symlink.settings" \
  "$_ws_settings_source" \
  "$_WS_USER_DIR/settings.json"

# ── Keybindings.json (with optional per-machine override) ──────────────────
_ws_keybindings_source="$DOTFILES_DIR/windsurf/keybindings.json"
[ -f "$_WS_LOCAL/keybindings.override.json5" ] && _ws_keybindings_source="$_WS_LOCAL/keybindings.override.json5"
check_symlink "windsurf.symlink.keybindings" \
  "$_ws_keybindings_source" \
  "$_WS_USER_DIR/keybindings.json"

# Skip app-dependent checks if Windsurf isn't installed.
# This file is always sourced by dotfiles-doctor, so `return` is the right
# control-flow primitive here.
[ -d "$_WS_APP" ] || return 0

# ── Font shared with jetbrains module (advisory; module/jetbrains/ enforces) ─
check_advisory "windsurf.font.jetbrains_mono_nerd" \
  "JetBrainsMono Nerd Font available (shared with jetbrains module)" \
  "fc-list 2>/dev/null | grep -qi 'JetBrainsMono Nerd Font'" \
  "Install via Brewfile: 'brew install --cask font-jetbrains-mono-nerd-font' (already in dotfiles Brewfile)"

# ── Extensions ────────────────────────────────────────────────────────────
# Compute the desired-installed set (one id per line, strip comments / blanks).
_ws_desired_extensions() {
  local list
  for list in "${_WS_EXT_LISTS[@]}"; do
    [ -f "$list" ] || continue
    grep -v '^#' "$list" | grep -v '^$' | tr -d ' \t'
  done | sort -u
}

# Lowercase comparison — windsurf --list-extensions returns lowercased ids.
_ws_installed_extensions() {
  [ -x "$_WS_BIN" ] || return 0
  "$_WS_BIN" --list-extensions 2>/dev/null | tr '[:upper:]' '[:lower:]' | sort -u
}

_ws_extension_installed() {
  local ext="$1"
  ext_lc="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
  _ws_installed_extensions | grep -Fxq "$ext_lc"
}

# Materialise (and cache) a Node-compatible CA bundle from the macOS system
# keychain. Windsurf's CLI uses Electron's bundled Node which doesn't honour
# the keychain — corporate TLS-inspection certs (internal
# CAs) need to be exported to a PEM and passed via NODE_EXTRA_CA_CERTS.
#
# The bundle lives at $_WS_LOCAL/ca-bundle.pem and is regenerated if missing
# or older than 30 days. Machine-local, never committed to git. We materialise
# at module-source time so the path is known at fix-command-string-construction
# time (the doctor's `_fix` wrapper runs the fix in `bash -c` — a fresh shell
# that doesn't see this module's helper functions).
_WS_CA_BUNDLE="$_WS_LOCAL/ca-bundle.pem"
if [ ! -f "$_WS_CA_BUNDLE" ] || [ -n "$(find "$_WS_CA_BUNDLE" -mtime +30 2>/dev/null)" ]; then
  mkdir -p "$_WS_LOCAL"
  if {
    security find-certificate -a -p /Library/Keychains/System.keychain 2>/dev/null
    security find-certificate -a -p /System/Library/Keychains/SystemRootCertificates.keychain 2>/dev/null
  } > "$_WS_CA_BUNDLE.tmp" 2>/dev/null; then
    mv "$_WS_CA_BUNDLE.tmp" "$_WS_CA_BUNDLE"
  else
    rm -f "$_WS_CA_BUNDLE.tmp"
  fi
fi
# Build the env prefix once. If the bundle is missing for some reason, fall
# back to no override (works on networks without TLS inspection).
if [ -s "$_WS_CA_BUNDLE" ]; then
  _WS_INSTALL_ENV="NODE_EXTRA_CA_CERTS='$_WS_CA_BUNDLE'"
else
  _WS_INSTALL_ENV=""
fi

# Lengthen the per-fix timeout for this module's installs (extension downloads
# over a slow corp link routinely exceed the 30s default). Doctor honours the
# env var if set before the check runs.
export FIX_TIMEOUT="${FIX_TIMEOUT:-180}"

# Emit one check per extension. Fix command is fully inline (no shell function
# refs) because `_fix` wraps in `bash -c` which spawns a fresh subshell.
_ws_ext_tmp="$(mktemp)"
_ws_desired_extensions > "$_ws_ext_tmp" 2>/dev/null || true

if [ -s "$_ws_ext_tmp" ]; then
  while IFS= read -r _ws_ext; do
    [ -z "$_ws_ext" ] && continue
    # Slug for the check id: replace dots and slashes with underscores.
    _ws_slug="$(printf '%s' "$_ws_ext" | tr './' '__')"
    check "windsurf.extension.$_ws_slug" \
      "$_ws_ext installed" \
      "_ws_extension_installed '$_ws_ext'" \
      "$_WS_INSTALL_ENV '$_WS_BIN' --install-extension '$_ws_ext' --force"
  done < "$_ws_ext_tmp"
fi
rm -f "$_ws_ext_tmp"

# ── Cascade owned by agentbrew (advisory only — flag if missing) ───────────
# We don't manage ~/.codeium/windsurf/, but flag if the directory is missing
# so the operator knows agentbrew hasn't run yet on this machine.
check_advisory "windsurf.cascade.agentbrew_present" \
  "Cascade config dir present (~/.codeium/windsurf/ — agentbrew-managed)" \
  "[ -d '$HOME/.codeium/windsurf' ]" \
  "Run 'dotfiles apply' to merge the canonical Agentfile and materialise Cascade rules/skills/MCP."

# ── Cascade model tier (advisory only — protobuf is UI-managed) ─────────────
# Per AGENTS.md § Model Configuration, Windsurf is in the "Devin + Windsurf"
# tier-2 group → Claude Opus 4.8 Max + 1M Context toggle. The selection
# lives in a binary protobuf written by the Cascade UI; we deliberately
# don't write it from dotfiles (the schema is upstream-owned).
#
# The advisory is best-effort: we can verify the catalog includes the
# expected entries (proving Cascade fetched the right model list from the
# Codeium server) but cannot prove from the protobuf which entry the
# operator actually selected — that requires decoding the protobuf wire
# format, which is out of scope for a doctor check.
#
# Three states:
#   ✓  matched   — the catalog string `claude-opus-4-8-max` AND the
#                  `1M Context` capability string are both present
#   ⚠  drifted   — file exists but missing one or both strings (most
#                  likely Cascade hasn't refreshed the catalog yet; the
#                  operator should launch Windsurf once)
#   ⚠  absent    — the protobuf doesn't exist (Cascade hasn't run; handled
#                  cleanly by check_advisory's PASS-on-no-file semantics)
_ws_cascade_model_tier_matches() {
  local pb="$HOME/.codeium/windsurf/user_settings.pb"
  [ -f "$pb" ] || return 0  # absent → not advisory's concern (separate check)
  strings "$pb" 2>/dev/null | grep -qE "^claude-opus-4-8-max$" && \
    strings "$pb" 2>/dev/null | grep -qF "1M Context"
}
check_advisory "windsurf.cascade.model_tier" \
  "Cascade catalog has Opus 4.8 Max + 1M Context (operator must select in UI)" \
  "_ws_cascade_model_tier_matches" \
  "echo 'Open Windsurf → Cascade → model picker → select \"Claude Opus 4.8 Max\" and enable the \"1M Context\" toggle. If those options are absent, launch Windsurf once to refresh the catalog from the server.'"

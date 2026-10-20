#!/bin/bash
# Typed extension points for company plugins (issue #145, step 6).
#
# The core reads each verified plugin in plugins.lock and applies its
# contributions through these functions. Every step is checked against the
# plugin's declared capabilities first (lib/plugin-capabilities.sh).
# A plugin that fails verification is skipped and reported, never run.
#
# Needs lib/plugin.sh and lib/plugin-capabilities.sh sourced first.

# Prints "<name>\t<path>" for each locked plugin that passes plugin_verify.
# Prints a "skipped" line on stderr for each one that does not.
plugin_verified_list() {
  local name
  for name in $(plugin_lock_names); do
    if plugin_verify "$name" >/dev/null 2>&1; then
      printf '%s\t%s\n' "$name" "$(plugin_lock_get "$name" path)"
    else
      echo "skipped plugin $name: it does not match plugins.lock (run: dotfiles plugin verify $name)" >&2
    fi
  done
}

# plugin_contribution <plugin path> <key>: prints the absolute path of a
# contributes.<key> entry, or fails when the plugin does not contribute it.
plugin_contribution() {
  local rel
  rel="$(K="$2" yq -r '.contributes[strenv(K)] // ""' "$1/dotfiles-plugin.yaml" 2>/dev/null)"
  [ -n "$rel" ] || return 1
  printf '%s/%s' "$1" "$rel"
}

# ── 6a. Brewfile pass ──────────────────────────────────────────────────
# One `brew bundle --file` pass per plugin, after the core pass. Every tap
# must be listed in capabilities.brew.taps, and casks need
# capabilities.brew.casks: true. An undeclared entry refuses the whole
# plugin Brewfile (status 3). A failed bundle is reported as
# "unreachable (plugin <name>)", never as a silent pass.
plugin_brew_check() {
  local name="$1" brewfile="$2" tap status=0
  while IFS= read -r tap; do
    plugin_require "$name" brew_tap "$tap" || status=3
  done < <(sed -nE 's/^[[:space:]]*tap[[:space:]]+"([^"]+)".*/\1/p' "$brewfile")
  if grep -qE '^[[:space:]]*cask[[:space:]]+"' "$brewfile"; then
    plugin_require "$name" brew_cask "" || status=3
  fi
  return "$status"
}

plugin_brew_pass() {
  local name path brewfile failed=0
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    brewfile="$(plugin_contribution "$path" brewfile)" || continue
    [ -f "$brewfile" ] || { echo "plugin $name: Brewfile missing: $brewfile" >&2; failed=1; continue; }
    if ! plugin_brew_check "$name" "$brewfile"; then
      echo "plugin $name: Brewfile refused (undeclared capability)" >&2
      failed=1
      continue
    fi
    echo "→ brew bundle for plugin $name"
    if ! brew bundle --no-upgrade --file="$brewfile"; then
      echo "brew bundle: unreachable (plugin $name)" >&2
      failed=1
    fi
  done < <(plugin_verified_list)
  return "$failed"
}

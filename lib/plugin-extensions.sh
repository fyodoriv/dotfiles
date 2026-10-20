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

# ── 6b. LaunchAgent templates ──────────────────────────────────────────
# A plugin ships plist templates in contributes.launchagents (a folder).
# The core renders them (@HOME@ and @PLUGIN_DIR@ placeholders), checks each
# Label against capabilities.launchagents, installs, and reloads. Plugins
# never edit core plists. Installed labels are recorded per plugin, so
# `plugin remove` can unload and delete them.

plugin_launchagents_dir() {
  printf '%s' "${DOTFILES_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
}

_plugin_state_file() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/plugins"
  mkdir -p "$dir"
  printf '%s/%s.%s' "$dir" "$1" "$2"
}

_plugin_plist_label() {
  plutil -extract Label raw -o - "$1" 2>/dev/null
}

# plugin_launchagents_render <name> <path>: installs and reloads changed
# agents. Returns 3 when any Label is not declared (nothing is installed
# for that template).
plugin_launchagents_render() {
  local name="$1" path="$2" src tmpl rendered label dest state status=0
  src="$(plugin_contribution "$path" launchagents)" || return 0
  [ -d "$src" ] || { echo "plugin $name: launchagents folder missing: $src" >&2; return 1; }
  state="$(_plugin_state_file "$name" launchagents)"
  : > "$state.new"
  for tmpl in "$src"/*.plist; do
    [ -f "$tmpl" ] || continue
    rendered="$(mktemp)"
    sed -e "s|@HOME@|$HOME|g" -e "s|@PLUGIN_DIR@|$path|g" "$tmpl" > "$rendered"
    label="$(_plugin_plist_label "$rendered")"
    if [ -z "$label" ]; then
      echo "plugin $name: $(basename "$tmpl") has no Label" >&2
      rm -f "$rendered"; status=1; continue
    fi
    if ! plugin_launchagent_check "$name" "$label"; then
      rm -f "$rendered"; status=3; continue
    fi
    dest="$(plugin_launchagents_dir)/$label.plist"
    echo "$label" >> "$state.new"
    if [ -f "$dest" ] && cmp -s "$rendered" "$dest"; then
      rm -f "$rendered"; continue
    fi
    mkdir -p "$(plugin_launchagents_dir)"
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    mv "$rendered" "$dest"
    launchctl bootstrap "gui/$(id -u)" "$dest" >/dev/null 2>&1 ||
      echo "plugin $name: could not load $label" >&2
    echo "→ loaded $label (plugin $name)"
  done
  mv "$state.new" "$state"
  return "$status"
}

plugin_launchagents_pass() {
  local name path failed=0
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    plugin_launchagents_render "$name" "$path" || failed=1
  done < <(plugin_verified_list)
  return "$failed"
}

# plugin_launchagents_remove <name>: unloads and deletes recorded agents.
plugin_launchagents_remove() {
  local state label
  state="$(_plugin_state_file "$1" launchagents)"
  [ -f "$state" ] || return 0
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    rm -f "$(plugin_launchagents_dir)/$label.plist"
  done < "$state"
  rm -f "$state"
}

# ── 6d. Shell fragments ────────────────────────────────────────────────
# A plugin with capabilities.shell_fragment: true may contribute one zsh
# fragment (contributes.shell). The core writes one generated file that
# sources each verified fragment in lock order. home/zshrc sources that
# file after core setup and before ~/.zshrc.local.

plugin_shell_file() {
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/plugin-shell.zsh"
}

plugin_shell_pass() {
  local name path fragment out tmp failed=0
  out="$(plugin_shell_file)"
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp "$out.XXXXXX")"
  echo "# Generated by dotfiles (lib/plugin-extensions.sh). Do not edit." > "$tmp"
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    fragment="$(plugin_contribution "$path" shell)" || continue
    if ! plugin_require "$name" shell_fragment; then
      failed=1; continue
    fi
    [ -f "$fragment" ] || { echo "plugin $name: shell fragment missing: $fragment" >&2; failed=1; continue; }
    printf '# plugin %s\n[ -f %q ] && source %q\n' "$name" "$fragment" "$fragment" >> "$tmp"
  done < <(plugin_verified_list)
  mv "$tmp" "$out"
  return "$failed"
}

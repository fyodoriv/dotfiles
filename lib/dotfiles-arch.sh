#!/bin/bash
# Shared machine / Homebrew architecture helpers.
#
# Usage:
#   source "$DOTFILES_DIR/lib/dotfiles-arch.sh"
#   dotfiles_brew_prefix          # /opt/homebrew or /usr/local
#   dotfiles_is_apple_silicon     # hw.optional.arm64 == 1
#   dotfiles_is_rosetta           # shell running under Rosetta translation

dotfiles_machine_arch() {
  uname -m 2>/dev/null || echo unknown
}

dotfiles_is_apple_silicon() {
  [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]
}

dotfiles_is_rosetta() {
  [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]
}

# Preferred Homebrew prefix for the current shell architecture.
dotfiles_brew_prefix() {
  if [ -n "${DOTFILES_BREW_PREFIX:-}" ]; then
    printf '%s\n' "$DOTFILES_BREW_PREFIX"
    return 0
  fi
  if [ -d /opt/homebrew/bin/brew ] && { [ "$(dotfiles_machine_arch)" = "arm64" ] || dotfiles_is_apple_silicon; }; then
    printf '/opt/homebrew\n'
  elif [ -d /usr/local/bin/brew ]; then
    printf '/usr/local\n'
  else
    printf '/opt/homebrew\n'
  fi
}

# True when Apple Silicon hardware should use native /opt/homebrew, not Intel brew.
dotfiles_expects_native_homebrew() {
  dotfiles_is_apple_silicon && [ "$(dotfiles_machine_arch)" = "arm64" ] && ! dotfiles_is_rosetta
}

# GUI apps configured in macos-apps.sh — must not force x86_64 Rosetta on Apple Silicon.
# Format per line: "DisplayName:fallback.bundle.id"
dotfiles_managed_app_entries() {
  cat <<'EOF'
Windsurf:com.exafunction.windsurf
Cursor:com.todesktop.230313mzl4w4u92
Slack:com.tinyspeck.slackmacgap
Google Chrome:com.google.Chrome
Microsoft Outlook:com.microsoft.Outlook
Ghostty:com.mitchellh.ghostty
Terminal:com.apple.Terminal
EOF
}

dotfiles_app_bundle_id_for_name() {
  local app_name="$1"
  local fallback_bundle_id="$2"
  osascript -e "id of app \"$app_name\"" 2>/dev/null || printf '%s\n' "$fallback_bundle_id"
}

dotfiles_app_has_x86_ls_priority() {
  local bundle_id="$1"
  defaults read "$bundle_id" LSArchitecturePriority 2>/dev/null | grep -q x86_64
}

dotfiles_clear_app_ls_architecture_priority() {
  local bundle_id="$1"
  defaults delete "$bundle_id" LSArchitecturePriority 2>/dev/null || true
}

# Clear legacy LSArchitecturePriority=x86_64 overrides for all managed apps.
dotfiles_clear_managed_app_rosetta_overrides() {
  dotfiles_is_apple_silicon || return 0
  local entry app_name bundle_id
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    app_name="${entry%%:*}"
    bundle_id="${entry#*:}"
    bundle_id="$(dotfiles_app_bundle_id_for_name "$app_name" "$bundle_id")"
    dotfiles_clear_app_ls_architecture_priority "$bundle_id"
  done < <(dotfiles_managed_app_entries)
}

# True when every installed managed app lacks an x86_64 LSArchitecturePriority override.
dotfiles_managed_apps_have_no_x86_override() {
  dotfiles_is_apple_silicon || return 0
  local entry app_name bundle_id app_path
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    app_name="${entry%%:*}"
    bundle_id="${entry#*:}"
    bundle_id="$(dotfiles_app_bundle_id_for_name "$app_name" "$bundle_id")"
    app_path="/Applications/${app_name}.app"
    [ -d "$app_path" ] || continue
    if dotfiles_app_has_x86_ls_priority "$bundle_id"; then
      return 1
    fi
  done < <(dotfiles_managed_app_entries)
  return 0
}

# True when an .app bundle ships an arm64 slice (arm64-only or universal).
dotfiles_app_binary_includes_arm64() {
  local app_path="$1"
  local main_exe app_basename
  [ -d "$app_path" ] || return 0
  app_basename="$(basename "$app_path" .app)"
  main_exe="$app_path/Contents/MacOS/$app_basename"
  [ -x "$main_exe" ] || return 0
  file "$main_exe" 2>/dev/null | grep -q arm64
}

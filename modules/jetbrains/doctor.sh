#!/bin/bash
# Doctor checks for the jetbrains module.
# Manages settings and plugins for all detected JetBrains IDEs.
#
# User overrides (machine-local, never committed to git):
#   $JETBRAINS_LOCAL_DIR/disabled_extra.txt  — extra plugins to disable
#   $JETBRAINS_LOCAL_DIR/enabled_override.txt — plugins to keep enabled
#
# Plugin resolution: final = (base ∪ extra) - enabled_override
# User settings take priority: enabled_override wins over the base list;
# fix mode preserves any plugins the user disabled through the IDE UI.

_JB_LOCAL="${JETBRAINS_LOCAL_DIR:-$HOME/.local/share/dotfiles-jetbrains}"
_JB_DISABLED_BASE="$DOTFILES_DIR/jetbrains/disabled_plugins.txt"
_JB_DISABLED_EXTRA="$_JB_LOCAL/disabled_extra.txt"
_JB_ENABLED_OVERRIDE="$_JB_LOCAL/enabled_override.txt"

# ── Plugin helpers ────────────────────────────────────────────────────────

# Compute desired-disabled set: (base ∪ extra) - enabled_override
_jb_desired_disabled() {
  local tmp
  tmp=$(mktemp -d)
  {
    [ -f "$_JB_DISABLED_BASE" ]  && grep -v '^#' "$_JB_DISABLED_BASE"  | grep -v '^$'
    [ -f "$_JB_DISABLED_EXTRA" ] && grep -v '^#' "$_JB_DISABLED_EXTRA" | grep -v '^$'
  } | sort -u > "$tmp/desired"
  if [ -f "$_JB_ENABLED_OVERRIDE" ]; then
    grep -v '^#' "$_JB_ENABLED_OVERRIDE" | grep -v '^$' > "$tmp/override"
    grep -Fxv -f "$tmp/override" "$tmp/desired" > "$tmp/result" || true
    cat "$tmp/result"
  else
    cat "$tmp/desired"
  fi
  rm -rf "$tmp"
}

# Checking direction: all desired-disabled plugins exist in IDE's disabled list
_jb_check_disabled() {
  local ide_dir="$1" tmp missing
  [ -f "$ide_dir/disabled_plugins.txt" ] || return 1
  tmp=$(mktemp -d)
  _jb_desired_disabled | sort > "$tmp/desired"
  grep -v '^#' "$ide_dir/disabled_plugins.txt" 2>/dev/null | grep -v '^$' | sort > "$tmp/current"
  missing=$(comm -23 "$tmp/desired" "$tmp/current" | grep . || true)
  rm -rf "$tmp"
  [ -z "$missing" ]
}

# Unchecking direction: no enabled_override plugin appears in IDE's disabled list
_jb_check_enabled() {
  local ide_dir="$1"
  [ -f "$_JB_ENABLED_OVERRIDE" ] || return 0
  [ -f "$ide_dir/disabled_plugins.txt" ] || return 0
  local tmp wrongly_disabled
  tmp=$(mktemp -d)
  grep -v '^#' "$_JB_ENABLED_OVERRIDE" | grep -v '^$' > "$tmp/override"
  wrongly_disabled=$(grep -Fxf "$tmp/override" "$ide_dir/disabled_plugins.txt" 2>/dev/null | grep . || true)
  rm -rf "$tmp"
  [ -z "$wrongly_disabled" ]
}

# Fix: write merged disabled_plugins.txt, preserving user-disabled plugins,
# removing enabled_override entries.
_jb_apply_plugins() {
  local ide_dir="$1" target tmp
  target="$ide_dir/disabled_plugins.txt"
  tmp=$(mktemp -d)
  _jb_desired_disabled > "$tmp/desired"
  # Remove broken symlinks left over from repo-path changes
  [ -L "$target" ] && [ ! -e "$target" ] && rm -f "$target"
  [ -f "$target" ] && grep -v '^#' "$target" | grep -v '^$' > "$tmp/current" || touch "$tmp/current"
  sort -u "$tmp/desired" "$tmp/current" > "$tmp/merged"
  if [ -f "$_JB_ENABLED_OVERRIDE" ]; then
    grep -v '^#' "$_JB_ENABLED_OVERRIDE" | grep -v '^$' > "$tmp/override"
    grep -Fxv -f "$tmp/override" "$tmp/merged" > "$tmp/final" || true
    mv "$tmp/final" "$tmp/merged"
  fi
  mv "$tmp/merged" "$target"
  rm -rf "$tmp"
}

# ── IDE detection ─────────────────────────────────────────────────────────

# Emit "<slug>\t<dir>" for the latest version of each detected IDE.
# slug = lowercase IDE name without version (e.g. "webstorm", "goland").
_jb_find_ides() {
  local jb_root="$HOME/Library/Application Support/JetBrains"
  [ -d "$jb_root" ] || return 0
  find "$jb_root" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | \
    grep -E '/[A-Za-z]{2,}[0-9]+\.[0-9]' | \
    sort -V | \
    while IFS= read -r dir; do
      local base slug
      base=$(basename "$dir")
      slug=$(printf '%s' "$base" | sed 's/[0-9].*//' | tr '[:upper:]' '[:lower:]')
      [ -n "$slug" ] && printf '%s\t%s\n' "$slug" "$dir"
    done | \
    awk -F'\t' '{ last[$1] = $2 } END { for (s in last) print s "\t" last[s] }'
}

# Map IDE slug to its vmoptions filename.
_jb_vmo_file() {
  case "$1" in
    webstorm)                        echo "webstorm.vmoptions" ;;
    goland)                          echo "goland.vmoptions" ;;
    idea|intellijidea)               echo "idea.vmoptions" ;;
    pycharm|pycharmce|pycharmcommunity) echo "pycharm.vmoptions" ;;
    rider)                           echo "rider.vmoptions" ;;
    clion)                           echo "clion.vmoptions" ;;
    datagrip)                        echo "datagrip.vmoptions" ;;
    phpstorm)                        echo "phpstorm.vmoptions" ;;
    rubymine)                        echo "rubymine.vmoptions" ;;
    aqua)                            echo "aqua.vmoptions" ;;
    *)                               echo "" ;;
  esac
}

# ── IdeaVim (always) ────────────────────────────────────────────────────────
check_symlink "symlink.ideavimrc" \
  "$DOTFILES_DIR/home/ideavimrc" \
  "$HOME/.ideavimrc"

# ── Per-IDE settings ─────────────────────────────────────────────────────────
while IFS=$'\t' read -r _jb_slug _jb_dir; do

  # Editor settings
  check_symlink "symlink.editor.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/editor.xml" \
    "$_jb_dir/options/editor.xml"

  # Editor font (with optional per-machine override at $_JB_LOCAL/editor-font.override.xml)
  _jb_editor_font_source="$DOTFILES_DIR/jetbrains/editor-font.xml"
  [ -f "$_JB_LOCAL/editor-font.override.xml" ] && _jb_editor_font_source="$_JB_LOCAL/editor-font.override.xml"
  check_symlink "symlink.editor_font.$_jb_slug" \
    "$_jb_editor_font_source" \
    "$_jb_dir/options/editor-font.xml"

  # Terminal font (with optional per-machine override at $_JB_LOCAL/terminal-font.override.xml)
  _jb_terminal_font_source="$DOTFILES_DIR/jetbrains/terminal-font.xml"
  [ -f "$_JB_LOCAL/terminal-font.override.xml" ] && _jb_terminal_font_source="$_JB_LOCAL/terminal-font.override.xml"
  check_symlink "symlink.terminal_font.$_jb_slug" \
    "$_jb_terminal_font_source" \
    "$_jb_dir/options/terminal-font.xml"

  # UI / file-nesting (JetBrains stores this as ui.lnf.xml)
  check_symlink "symlink.ui.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/ui.xml" \
    "$_jb_dir/options/ui.lnf.xml"

  # Code style
  check_symlink "symlink.codestyle.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/codestyle.xml" \
    "$_jb_dir/codestyles/Default.xml"

  # Keymap (macOS variant)
  check_symlink "symlink.keymap.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/keymap.xml" \
    "$_jb_dir/keymaps/Mac OS X 10_5_ copy.xml"

  # Custom scope
  check_symlink "symlink.scope_all_repos.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/scopes/All_Repos_Clean.xml" \
    "$_jb_dir/scopes/All_Repos_Clean.xml"

  # IDE properties
  check_symlink "symlink.properties.$_jb_slug" \
    "$DOTFILES_DIR/jetbrains/idea.properties" \
    "$_jb_dir/idea.properties"

  # VM options (IDE-specific; only applied when dotfiles has a matching file)
  _jb_vmo=$(_jb_vmo_file "$_jb_slug")
  if [ -n "$_jb_vmo" ] && [ -f "$DOTFILES_DIR/jetbrains/$_jb_vmo" ]; then
    check_symlink "symlink.vmoptions.$_jb_slug" \
      "$DOTFILES_DIR/jetbrains/$_jb_vmo" \
      "$_jb_dir/$_jb_vmo"
  fi

  # Plugins — checking direction: desired-disabled plugins are in IDE's list
  check "plugins.disabled.$_jb_slug" \
    "desired plugins disabled in $_jb_slug" \
    "_jb_check_disabled '$_jb_dir'" \
    "_jb_apply_plugins '$_jb_dir'"

  # Plugins — unchecking direction: enabled_override plugins NOT in IDE's list
  if [ -f "$_JB_ENABLED_OVERRIDE" ]; then
    check "plugins.enabled.$_jb_slug" \
      "override-enabled plugins not disabled in $_jb_slug" \
      "_jb_check_enabled '$_jb_dir'" \
      "_jb_apply_plugins '$_jb_dir'"
  fi

done < <(_jb_find_ides)

# ── Recommended plugins (advisory only — does NOT auto-install) ──────────────
# Lists `jetbrains/recommended_plugins.txt` plugins that are not yet installed
# in ANY detected JetBrains IDE. Advisory rather than enforcing because:
#   1. JetBrains plugins update on their own schedule; force-installing on every
#      doctor run would churn the IDE state.
#   2. `installPlugins` fails if the IDE is open — the doctor shouldn't gate on
#      whether WebStorm is running.
#   3. The operator can run `bin/jetbrains-install-plugins` on demand.
_JB_RECOMMENDED="$DOTFILES_DIR/jetbrains/recommended_plugins.txt"
if [ -f "$_JB_RECOMMENDED" ]; then
  _jb_recommended_installed() {
    local plugin="$1"
    # Check each detected IDE's plugins dir for the plugin.
    #
    # JetBrains stores each plugin as a directory under
    #   ~/Library/Application Support/JetBrains/<IDE>/plugins/<dir>/
    # with the plugin code inside `lib/*.jar`. Plugin metadata lives in
    # `META-INF/plugin.xml` INSIDE the jar (zip archive), so a plain
    # `grep '<id>$plugin</id>' *.jar` returns nothing — jars are binary.
    #
    # Three-tier check (fastest first):
    #  1. Loose `plugin.xml` next to the jar (rare — older plugins).
    #  2. Directory name equals the plugin id verbatim (handles the
    #     "Key Promoter X", "Mermaid" naming convention).
    #  3. `unzip -p <jar> META-INF/plugin.xml | grep -q '<id>$plugin</id>'`
    #     — authoritative read of every installed jar.
    while IFS=$'\t' read -r _slug _dir; do
      [ -d "$_dir/plugins" ] || continue

      # Tier 1: loose plugin.xml (legacy layout)
      if find "$_dir/plugins" -maxdepth 3 -name "plugin.xml" \
          -exec grep -l "<id>$plugin</id>" {} + 2>/dev/null \
          | head -1 | grep -q .; then
        return 0
      fi

      # Tier 2: directory named after the plugin (modern marketplace layout)
      if [ -d "$_dir/plugins/$plugin" ]; then
        return 0
      fi

      # Tier 3: unzip plugin.xml from each jar and grep
      while IFS= read -r _jar; do
        [ -z "$_jar" ] && continue
        if unzip -p "$_jar" META-INF/plugin.xml 2>/dev/null \
            | grep -q "<id>$plugin</id>"; then
          return 0
        fi
      done < <(find "$_dir/plugins" -maxdepth 3 -name "*.jar" 2>/dev/null)
    done < <(_jb_find_ides)
    return 1
  }
  while IFS= read -r _line; do
    case "$_line" in
      '#'*|'') continue ;;
    esac
    # Plugin IDs may contain literal spaces (e.g. "Key Promoter X"). Strip a
    # trailing inline comment (2+ spaces then `#…`) instead of cutting at the
    # first space.
    _plugin_id="$(printf '%s' "$_line" | sed -E 's/[[:space:]]{2,}#.*$//; s/[[:space:]]+$//')"
    [ -z "$_plugin_id" ] && continue
    # Slug must be filesystem/check-id safe; spaces and dots collapse to `_`.
    _slug="$(printf '%s' "$_plugin_id" | tr '. /' '___')"
    # Real check (not advisory): `bin/jetbrains-install-plugins` is graceful
    # about running IDEs — it skips them with a warning and exits 0. Doctor
    # --fix re-installs missing plugins in any closed IDE on every run. If
    # the only IDE is open, the script logs the close-and-retry hint and
    # exits 0; the check stays red until the operator closes the IDE and
    # the fixer runs again. FIX_TIMEOUT lengthened because plugin downloads
    # over a slow corp link can exceed the 30s default.
    check "plugins.recommended.$_slug" \
      "$_plugin_id installed in some JetBrains IDE" \
      "_jb_recommended_installed '$_plugin_id'" \
      "FIX_TIMEOUT=180 '$DOTFILES_DIR/bin/jetbrains-install-plugins'"
  done < "$_JB_RECOMMENDED"
fi

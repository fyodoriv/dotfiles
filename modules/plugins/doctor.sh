#!/bin/bash
# Doctor checks for company plugins in plugins.lock (issue #145).
# A plugin that no longer matches its lock entry is disabled: the core
# lookup skips it, and this check fails with the difference.

# shellcheck source=../../lib/plugin.sh
source "$DOTFILES_DIR/lib/plugin.sh"

if command -v yq >/dev/null 2>&1; then
  for _plugin_name in $(plugin_lock_names); do
    check "plugins.$_plugin_name.verified" \
      "plugin $_plugin_name matches plugins.lock (fix: dotfiles plugin remove $_plugin_name, then add it again)" \
      "plugin_verify '$_plugin_name'" \
      ""
    # Blocked software listed by the plugin (data only; the core scans).
    _plugin_root="$(plugin_lock_get "$_plugin_name" path)"
    _plugin_blocked="$(N="$_plugin_name" yq -r '.contributes.blocked_software // ""' "$_plugin_root/dotfiles-plugin.yaml" 2>/dev/null)"
    if [ -n "$_plugin_blocked" ] && [ -f "$_plugin_root/$_plugin_blocked" ] && plugin_verify "$_plugin_name" >/dev/null 2>&1; then
      # shellcheck source=../../lib/blocked-software.sh
      source "$DOTFILES_DIR/lib/blocked-software.sh"
      check "plugins.$_plugin_name.blocked_software" \
        "no software that plugin $_plugin_name blocks is installed (fix: uninstall each item that blocked_software_found '$_plugin_root/$_plugin_blocked' prints)" \
        "[ -z \"\$(blocked_software_found '$_plugin_root/$_plugin_blocked')\" ]" \
        ""
    fi
    if [ "$(plugin_lock_get "$_plugin_name" dev)" = true ]; then
      audit_warn "plugin $_plugin_name is a dev link: not pinned or verified"
    fi
  done
  unset _plugin_name _plugin_root _plugin_blocked
fi

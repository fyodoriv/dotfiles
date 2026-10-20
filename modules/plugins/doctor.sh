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
    if [ "$(plugin_lock_get "$_plugin_name" dev)" = true ]; then
      audit_warn "plugin $_plugin_name is a dev link: not pinned or verified"
    fi
  done
  unset _plugin_name
fi

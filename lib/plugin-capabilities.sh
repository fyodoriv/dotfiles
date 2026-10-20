#!/bin/bash
# Capability enforcement for company plugins (issue #145, step 5).
#
# A plugin declares its capabilities in dotfiles-plugin.yaml. The core runs
# plugin steps only through the helpers below. Each helper checks the
# declaration first. Anything not declared is refused with exit status 3:
#
#   capability not declared: <kind> <value> (plugin <name>)
#
# Kinds and how a value matches:
#   launchagents, defaults_write, network_hosts, secrets, hooks
#                 the value matches one listed glob (for example com.acme.*)
#   brew_tap      the value is listed in capabilities.brew.taps
#   brew_cask     capabilities.brew.casks is true
#   sudo          capabilities.sudo is true (the helper also asks at a TTY)
#   shell_fragment capabilities.shell_fragment is true
#
# Uses lib/plugin.sh (lock helpers). Source that first.

# Prints the manifest path of locked plugin "$1".
_plugin_manifest() {
  local path
  path="$(plugin_lock_get "$1" path)" || return 1
  [ -n "$path" ] && [ -f "$path/dotfiles-plugin.yaml" ] || return 1
  printf '%s/dotfiles-plugin.yaml' "$path"
}

# plugin_capability_allows <name> <kind> <value>: succeeds when declared.
plugin_capability_allows() {
  local name="$1" kind="$2" value="${3:-}" manifest pattern
  manifest="$(_plugin_manifest "$name")" || return 1
  case "$kind" in
    launchagents | defaults_write | network_hosts | secrets | hooks)
      while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        # shellcheck disable=SC2053  # the declared value is a glob on purpose
        [[ "$value" == $pattern ]] && return 0
      done < <(K="$kind" yq -r '.capabilities[strenv(K)] // [] | .[]' "$manifest" 2>/dev/null)
      return 1 ;;
    brew_tap)
      V="$value" yq -e '(.capabilities.brew.taps // []) | any_c(. == strenv(V))' "$manifest" >/dev/null 2>&1 ;;
    brew_cask)
      [ "$(yq -r '.capabilities.brew.casks // false' "$manifest")" = true ] ;;
    sudo | shell_fragment)
      K="$kind" yq -e '.capabilities[strenv(K)] == true' "$manifest" >/dev/null 2>&1 ;;
    *)
      return 1 ;;
  esac
}

# plugin_require <name> <kind> [<value>]: returns 3 with the standard
# message when the capability is not declared.
plugin_require() {
  if plugin_capability_allows "$@"; then
    return 0
  fi
  echo "capability not declared: $2${3:+ $3} (plugin $1)" >&2
  return 3
}

# Prints the lock name of the plugin installed at "$1", if any.
plugin_name_for_root() {
  local name
  for name in $(plugin_lock_names); do
    if [ "$(plugin_lock_get "$name" path)" = "$1" ]; then
      printf '%s' "$name"
      return 0
    fi
  done
  return 1
}

# ── Helpers that run plugin steps ──────────────────────────────────────

# plugin_defaults_write <name> <domain> <args...>
plugin_defaults_write() {
  plugin_require "$1" defaults_write "$2" || return
  shift
  defaults write "$@"
}

# plugin_launchagent_check <name> <label>: call before installing a
# rendered LaunchAgent for a plugin.
plugin_launchagent_check() {
  plugin_require "$1" launchagents "$2"
}

# plugin_brew_tap <name> <tap>
plugin_brew_tap() {
  plugin_require "$1" brew_tap "$2" || return
  brew tap "$2"
}

# plugin_sudo <name> <command...>: needs the capability and a person at a
# terminal who confirms. Agents and LaunchAgents cannot pass this.
plugin_sudo() {
  local name="$1" answer
  shift
  plugin_require "$name" sudo || return
  [ -t 0 ] || { echo "plugin $name asks for sudo; run it in a terminal" >&2; return 3; }
  printf 'Plugin %s wants to run with sudo: %s\nAllow? [y/N] ' "$name" "$*" >&2
  read -r answer
  [ "$answer" = y ] || [ "$answer" = Y ] || return 3
  sudo "$@"
}

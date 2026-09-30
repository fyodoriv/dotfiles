#!/bin/bash
# Shared PATH + env setup so scripts avoid /usr/bin/{curl,grep,jq,find} endpoint-agent hits.
#
# Usage:
#   source "$DOTFILES_DIR/lib/dotfiles-endpoint-paths.sh"
#   dotfiles_prepend_endpoint_tool_paths "$DOTFILES_DIR/bin"
#
# LaunchAgents, chezmoi scripts, and doctor runs use a minimal PATH — prepend
# dotfiles shims (bin/curl, bin/jq, bin/grep) and keg-only Homebrew curl first.

# Resolve DOTFILES_DIR from a script living in dotfiles/bin/ when unset.
dotfiles_resolve_dir_from_bin_script() {
  local script_path="${1:-}"
  [ -n "$script_path" ] || return 1
  script_path="$(cd "$(dirname "$script_path")/.." && pwd 2>/dev/null)" || return 1
  [ -d "$script_path/bin" ] && [ -d "$script_path/lib" ] || return 1
  printf '%s\n' "$script_path"
}

# One-liner for LaunchAgent / chezmoi scripts: source lib, prepend shims.
dotfiles_bootstrap_endpoint_paths() {
  local script_path="${1:-${BASH_SOURCE[1]:-}}"
  local dotfiles_dir="${DOTFILES_DIR:-}"
  if [ -z "$dotfiles_dir" ]; then
    dotfiles_dir="$(dotfiles_resolve_dir_from_bin_script "$script_path" 2>/dev/null || true)"
  fi
  if [ -z "$dotfiles_dir" ] && [ -n "${DOTFILES_DIR:-}" ]; then
    dotfiles_dir="$DOTFILES_DIR"
  fi
  [ -n "$dotfiles_dir" ] || return 0
  # shellcheck disable=SC1091
  source "$dotfiles_dir/lib/dotfiles-endpoint-paths.sh"
  dotfiles_prepend_endpoint_tool_paths "$dotfiles_dir/bin"
}

dotfiles_prepend_endpoint_tool_paths() {
  local dotfiles_bin="${1:-}"
  local path_prefix=""

  if [ -n "$dotfiles_bin" ] && [ -d "$dotfiles_bin" ]; then
    path_prefix="$dotfiles_bin"
  fi

  if [ -d "${HOME}/.local/bin" ]; then
    if [ -n "$path_prefix" ]; then
      path_prefix="${path_prefix}:${HOME}/.local/bin"
    else
      path_prefix="${HOME}/.local/bin"
    fi
  fi

  if [ -n "${DOTFILES_BREW_PREFIX:-}" ]; then
    _brew_prefix="$DOTFILES_BREW_PREFIX"
  elif [ -d /opt/homebrew ]; then
    _brew_prefix="/opt/homebrew"
  else
    _brew_prefix="/usr/local"
  fi

  for _cdir in "$_brew_prefix/opt/curl/bin" /usr/local/opt/curl/bin; do
    if [ -d "$_cdir" ]; then
      if [ -n "$path_prefix" ]; then
        path_prefix="${path_prefix}:$_cdir"
      else
        path_prefix="$_cdir"
      fi
    fi
  done

  if [ -n "$path_prefix" ]; then
    export PATH="$path_prefix:${PATH:-}"
  fi

  for _curl in "$_brew_prefix/opt/curl/bin/curl" /usr/local/opt/curl/bin/curl; do
    if [ -x "$_curl" ]; then
      export HOMEBREW_CURL_PATH="$_curl"
      break
    fi
  done

  unset _cdir _curl _brew_prefix
}

# fnm default Node bin (same layout as launchagents/com.dotfiles.gui-path.plist).
# Claude/Cursor SessionStart hooks must prepend this or npx-based MCP servers fail
# doctor health checks (npx lives under fnm, not ~/.local/bin).
dotfiles_resolve_fnm_node_bin() {
  local home="${1:-${HOME:-}}"
  [ -n "$home" ] || return 1
  local node_ver="" fnm_dir="$home/.local/share/fnm"
  if [ -f "$home/.node-version" ]; then
    node_ver="$(sed 's/^v//' "$home/.node-version" 2>/dev/null || true)"
  fi
  [ -n "$node_ver" ] || return 1
  local node_bin="$fnm_dir/node-versions/v${node_ver}/installation/bin"
  [ -d "$node_bin" ] && printf '%s\n' "$node_bin"
}

# True on a managed endpoint. Set DOTFILES_MANAGED_ENDPOINT=1, or list paths
# in the colon-separated DOTFILES_ENDPOINT_AGENT_APPS (true when any exists).
# Default: false. An org overlay sets these.
dotfiles_managed_endpoint() {
  [ "${DOTFILES_MANAGED_ENDPOINT:-0}" = "1" ] && return 0
  local apps="${DOTFILES_ENDPOINT_AGENT_APPS:-}" app
  [ -n "$apps" ] || return 1
  local IFS=':'
  for app in $apps; do
    [ -n "$app" ] && [ -e "$app" ] && return 0
  done
  return 1
}

# Corporate CA for Node HTTPS (matches home/zshenv): first existing file from
# the colon-separated DOTFILES_CORPORATE_CA_BUNDLES, then the local combined
# bundles under ~/.config/ssl.
dotfiles_corporate_node_ca() {
  local home="${1:-${HOME:-}}" ca
  local IFS=':'
  local -a extra=()
  # shellcheck disable=SC2206
  extra=(${DOTFILES_CORPORATE_CA_BUNDLES:-})
  for ca in \
    ${extra[@]+"${extra[@]}"} \
    "$home/.config/ssl/corporate-combined-ca.pem" \
    "$home/.config/ssl/macos-trust-bundle.pem"; do
    if [ -f "$ca" ]; then
      printf '%s\n' "$ca"
      return 0
    fi
  done
  return 1
}

# Prefix for agent session PATH: fnm node, dotfiles shims, ~/.local/bin.
dotfiles_agent_path_prefix() {
  local dotfiles_dir="${1:-}" home="${2:-${HOME:-}}"
  local -a parts=()
  local fnm_bin
  fnm_bin="$(dotfiles_resolve_fnm_node_bin "$home" 2>/dev/null || true)"
  [ -n "$fnm_bin" ] && parts+=("$fnm_bin")
  if [ -n "$dotfiles_dir" ] && [ -d "$dotfiles_dir/bin" ]; then
    parts+=("$dotfiles_dir/bin")
  fi
  if [ -n "$home" ] && [ -d "$home/.local/bin" ]; then
    parts+=("$home/.local/bin")
  fi
  local IFS=':'
  [ "${#parts[@]}" -gt 0 ] && printf '%s' "${parts[*]}"
}

dotfiles_resolve_find() {
  local dotfiles_bin="${1:-}" candidate file_type
  if [ -n "$dotfiles_bin" ] && [ -x "${dotfiles_bin}/find" ]; then
    candidate="${dotfiles_bin}/find"
    file_type="$(/usr/bin/file -b "$candidate" 2>/dev/null || true)"
    case "$file_type" in Mach-O*) printf '%s\n' "$candidate"; return 0 ;; esac
  fi
  for candidate in /opt/homebrew/bin/gfind /usr/local/bin/gfind     /opt/homebrew/opt/findutils/libexec/gnubin/find /usr/local/opt/findutils/libexec/gnubin/find; do
    [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
  done
  printf '%s\n' /usr/bin/find
}

# True when candidate exists, is executable, and (if symlink) target resolves.
dotfiles_tool_candidate_usable() {
  local candidate="$1" target=""
  [ -n "$candidate" ] || return 1
  [ -e "$candidate" ] || return 1
  [ -x "$candidate" ] || return 1
  if [ -L "$candidate" ]; then
    target="$(readlink "$candidate" 2>/dev/null || true)"
    [ -n "$target" ] || return 1
    case "$target" in
      /*) ;;
      *) target="$(cd "$(dirname "$candidate")" 2>/dev/null && pwd -P)/$target" ;;
    esac
    [ -x "$target" ] || return 1
  fi
  return 0
}

# Resolve jq for hook subprocesses (audit-logger, verify-before-completion, …).
# Prefer dotfiles/bin or ~/.local/bin symlinks to adhoc-signed Homebrew jq.
dotfiles_resolve_jq() {
  local dotfiles_dir="${1:-${DOTFILES_DIR:-}}" home="${2:-${HOME:-}}"
  local candidate

  if [ -n "$dotfiles_dir" ]; then
    candidate="${dotfiles_dir}/bin/jq"
    if dotfiles_tool_candidate_usable "$candidate"; then
      if [ -L "$candidate" ] || /usr/bin/file -b "$candidate" 2>/dev/null | grep -q 'Mach-O'; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  fi

  if [ -n "$home" ]; then
    candidate="${home}/.local/bin/jq"
    if dotfiles_tool_candidate_usable "$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in /opt/homebrew/bin/jq /usr/local/bin/jq; do
    [ -x "$candidate" ] && printf '%s\n' "$candidate" && return 0
  done

  command -v jq 2>/dev/null || true
}

# Resolve python3 / python3.13 for hook subprocesses (sessionStart, audit hooks).
# Prefer dotfiles/bin symlinks to adhoc-signed uv Mach-O.
dotfiles_resolve_python() {
  local dotfiles_dir="${1:-${DOTFILES_DIR:-}}" home="${2:-${HOME:-}}" name="${3:-python3}"
  local candidate

  if [ -n "$dotfiles_dir" ] && [ -x "${dotfiles_dir}/bin/${name}" ]; then
    candidate="${dotfiles_dir}/bin/${name}"
    if [ -L "$candidate" ] || /usr/bin/file -b "$candidate" 2>/dev/null | grep -q 'Mach-O'; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  if [ -n "$home" ] && [ -x "${home}/.local/bin/${name}" ]; then
    printf '%s\n' "${home}/.local/bin/${name}"
    return 0
  fi

  command -v "$name" 2>/dev/null || true
}

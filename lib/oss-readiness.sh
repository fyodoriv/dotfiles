#!/bin/bash
# OSS-readiness shared library: secret scanning, optional private-reference
# scanning, and optional private-email checks used by git hooks, tests,
# doctor modules, and CI.

export OSS_READINESS_INTERNAL_PATTERN="${OSS_READINESS_INTERNAL_PATTERN:-}"
export OSS_READINESS_PRIVATE_EMAIL_PATTERN="${OSS_READINESS_PRIVATE_EMAIL_PATTERN:-}"
export OSS_READINESS_ENV_FILE="${OSS_READINESS_ENV_FILE:-}"

OSS_READINESS_SECRET_PATTERNS=(
  'ghp_[A-Za-z0-9]{36}'
  'gho_[A-Za-z0-9]{36}'
  'ghu_[A-Za-z0-9]{36}'
  'ghs_[A-Za-z0-9]{36}'
  'ghr_[A-Za-z0-9]{36}'
  'AKIA[A-Z0-9]{16}'
  'ASIA[A-Z0-9]{16}'
  'xox[bpra]-[A-Za-z0-9-]{20,}'
  'sk_(live|test)_[A-Za-z0-9]{24,}'
  'npm_[A-Za-z0-9]{36}'
  'sk-ant-[A-Za-z0-9_-]{90,}'
  'sk-(proj-)?[A-Za-z0-9_-]{40,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

# Keys a pattern file may set. Any other line is ignored.
OSS_READINESS_ENV_KEYS=" OSS_READINESS_INTERNAL_PATTERN OSS_READINESS_PRIVATE_EMAIL_PATTERN OSS_READINESS_PATTERN_VERSION OSS_READINESS_ALLOWED_ROOTS OSS_READINESS_REPO "

# Reads a pattern file as DATA. It never runs the file (issue #145 gap S2).
# Each line is KEY=VALUE for a key in OSS_READINESS_ENV_KEYS, with an optional
# "export " prefix. A value in single quotes is literal. A value in double
# quotes may start with ${KEY:-} or $KEY of the same key, to append to it.
# Every other line, including comments, is ignored.
oss_readiness_parse_env_file() {
  local file="$1" line key value
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#export }"
    [[ "$line" =~ ^([A-Z_]+)=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "$OSS_READINESS_ENV_KEYS" in *" $key "*) ;; *) continue ;; esac
    if [[ "$value" =~ ^\'(.*)\'$ ]]; then
      value="${BASH_REMATCH[1]}"
    elif [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
      case "$value" in
        "\${$key:-}"*) value="${!key:-}${value#"\${$key:-}"}" ;;
        "\${$key}"*) value="${!key:-}${value#"\${$key}"}" ;;
        "\$$key"*) value="${!key:-}${value#"\$$key"}" ;;
      esac
    fi
    printf -v "$key" '%s' "$value"
    export "${key?}"
  done < "$file"
  return 0
}

# Prints the overlay root when one is configured or found, else nothing.
oss_readiness_overlay_root() {
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [ -f "$lib_dir/plugin.sh" ] || return 1
  # shellcheck source=lib/plugin.sh
  source "$lib_dir/plugin.sh"
  plugin_overlay_root 2>/dev/null
}

# Loads the private patterns. Order: $OSS_READINESS_ENV_FILE, then the
# well-known local file, then the overlay root. Files are parsed, never
# sourced, and folders found by glob are never read (issue #145 gap S2).
oss_readiness_load_private_env() {
  local candidate overlay_root
  if [ -n "${OSS_READINESS_ENV_FILE:-}" ] && [ -f "$OSS_READINESS_ENV_FILE" ]; then
    oss_readiness_parse_env_file "$OSS_READINESS_ENV_FILE"
    return 0
  fi

  # Well-known local-only candidate. Never committed; not part of any repo.
  candidate="${XDG_CONFIG_HOME:-$HOME/.config}/oss-readiness/oss-readiness.env"
  if [ -f "$candidate" ]; then
    oss_readiness_parse_env_file "$candidate"
    return 0
  fi

  overlay_root="$(oss_readiness_overlay_root || true)"
  if [ -n "$overlay_root" ] && [ -f "$overlay_root/oss-readiness.env" ]; then
    oss_readiness_parse_env_file "$overlay_root/oss-readiness.env"
    return 0
  fi
  return 1
}

# Fails, and prints the reason, when an overlay is installed but no private
# pattern is loaded. The leak gates then block instead of scanning with an
# empty pattern (issue #145 gap S1).
oss_readiness_check_overlay_patterns() {
  local overlay_root
  [ -z "${OSS_READINESS_INTERNAL_PATTERN:-}" ] || return 0
  overlay_root="$(oss_readiness_overlay_root || true)"
  [ -n "$overlay_root" ] || return 0
  echo "an overlay is installed ($overlay_root), but no private pattern is loaded; add OSS_READINESS_INTERNAL_PATTERN to ~/.config/oss-readiness/oss-readiness.env or to the overlay's oss-readiness.env"
  return 1
}

# Runs the installed overlay's own hook "$1" (hooks/<name>), when it is
# executable. Extra arguments go to the hook. Stdin goes to the hook.
# Returns the hook's exit status, or 0 when there is no such hook
# (issue #145 gap S4).
oss_readiness_run_overlay_hook() {
  local name="$1" overlay_root hook
  shift
  overlay_root="$(oss_readiness_overlay_root || true)"
  [ -n "$overlay_root" ] || return 0
  hook="$overlay_root/hooks/$name"
  [ -x "$hook" ] || return 0
  # A plugin from plugins.lock must declare the hook (issue #145, step 5).
  local lib_dir plugin
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "$lib_dir/plugin.sh" ] && [ -f "$lib_dir/plugin-capabilities.sh" ]; then
    # shellcheck source=lib/plugin.sh
    source "$lib_dir/plugin.sh"
    # shellcheck source=lib/plugin-capabilities.sh
    source "$lib_dir/plugin-capabilities.sh"
    if plugin="$(plugin_name_for_root "$overlay_root")"; then
      plugin_require "$plugin" hooks "$name" || return
    fi
  fi
  "$hook" "$@"
}

_oss_readiness_config_dir() {
  printf '%s\n' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config"
}

# Prints the owner's public repos as lower-case "host/owner/repo" lines.
oss_readiness_owner_public_repos() {
  local list="${DOTFILES_PUBLIC_PUSH_ALLOWLIST:-$(_oss_readiness_config_dir)/public-push-remotes.txt}"
  [ -r "$list" ] || return 0
  sed 's/#.*//; s/[[:space:]]//g' "$list" | grep -v '^$' | tr '[:upper:]' '[:lower:]'
}

# Succeeds when "$1" (a "host/owner/repo" key) is one of the owner's public
# repos. Only the owner can push there, so a push or post to one comes
# from the owner's machine.
oss_readiness_is_owner_public() {
  local key
  key="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  [ -n "$key" ] || return 1
  oss_readiness_owner_public_repos | grep -qxF -- "$key"
}

# Prints the lowest private pattern file version that a push or post to an
# owner's public repo accepts (config/oss-readiness-min-version).
oss_readiness_min_version() {
  local v
  v="$(tr -cd '0-9' 2>/dev/null < "$(_oss_readiness_config_dir)/oss-readiness-min-version" || true)"
  printf '%s\n' "${v:-1}"
}

# Succeeds when the loaded private env can guard a write to an owner's
# public repo: it has a private pattern, and its OSS_READINESS_PATTERN_VERSION
# is at least the minimum. Otherwise prints the reason and fails, so the
# caller blocks the write. A missing or outdated file fails closed: an
# outdated file let private references reach public repos before.
oss_readiness_check_private_env() {
  local min have
  min="$(oss_readiness_min_version)"
  if [ -z "${OSS_READINESS_INTERNAL_PATTERN:-}" ]; then
    echo "the private pattern file (~/.config/oss-readiness/oss-readiness.env) is missing or has no OSS_READINESS_INTERNAL_PATTERN"
    return 1
  fi
  have="${OSS_READINESS_PATTERN_VERSION:-0}"
  case "$have" in '' | *[!0-9]*) have=0 ;; esac
  if [ "$have" -lt "$min" ]; then
    echo "the private pattern file is version $have, and this dotfiles needs version $min or later; copy the current ~/.config/oss-readiness/ from the machine that has it"
    return 1
  fi
  return 0
}

# Prints one extended regex for the path globs in .oss-readiness-allow at
# revision "$2" of repo "$1" (one glob per line, # comments). Paths that
# match skip the generic marker scan; list only leak-guard test fixtures.
# Prints nothing when the file is missing or empty.
oss_readiness_allow_regex() {
  git -C "$1" show "$2:.oss-readiness-allow" 2>/dev/null |
    sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' |
    awk '{
      g = $0; r = ""
      for (i = 1; i <= length(g); i++) {
        c = substr(g, i, 1)
        if (c == "*" && substr(g, i + 1, 1) == "*") { r = r ".*"; i++ }
        else if (c == "*") r = r "[^/]*"
        else if (c == "?") r = r "[^/]"
        else if (index(".+()|[]{}^$\\", c)) r = r "\\" c
        else r = r c
      }
      out = out (out == "" ? "" : "|") "^" r "$"
    } END { if (out != "") print out }'
}

oss_readiness_email_is_safe() {
  local email="$1"
  [ -n "${OSS_READINESS_PRIVATE_EMAIL_PATTERN:-}" ] || return 0
  if printf '%s\n' "$email" | grep -Eq -- "$OSS_READINESS_PRIVATE_EMAIL_PATTERN"; then
    return 1
  fi
  return 0
}

oss_readiness_scan_internal_refs() {
  local hit=1 file
  [ -n "${OSS_READINESS_INTERNAL_PATTERN:-}" ] || return 1
  for file in "$@"; do
    [ -f "$file" ] || continue
    if grep -lIiE -- "$OSS_READINESS_INTERNAL_PATTERN" "$file" 2>/dev/null; then
      hit=0
    fi
  done
  return "$hit"
}

oss_readiness_scan_secrets() {
  local hit=1 file pattern hits
  for file in "$@"; do
    [ -f "$file" ] || continue
    case "$file" in
      */home/zshenv.secrets.example) continue ;;
      *.example) continue ;;
      */tests/*fixture*) continue ;;
      */tests/audit.bats) continue ;;
      */tests/module-security.bats) continue ;;
      */src/core/secret-detector.test.ts) continue ;;
      */src/lint.test.ts) continue ;;
      */src/mcp/env-vars.test.ts) continue ;;
      */src/mcp/mcp-wizard.test.ts) continue ;;
      */src/sync/mcp-sync-pure.test.ts) continue ;;
      */src/sync/mcp-sync.test.ts) continue ;;
      *.test.ts|*.test.js|*_test.go) continue ;;
    esac
    for pattern in "${OSS_READINESS_SECRET_PATTERNS[@]}"; do
      hits=$(grep -nIE -- "$pattern" "$file" 2>/dev/null \
        | grep -v '# dotfiles-secret-allowlist:' \
        | head -1)
      if [ -n "$hits" ]; then
        printf '%s: matches /%s/\n' "$file" "$pattern"
        hit=0
        break
      fi
    done
  done
  return "$hit"
}

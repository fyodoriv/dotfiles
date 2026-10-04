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

oss_readiness_load_private_env() {
  local repo="${1:-dotfiles}" candidate overlay_root
  if [ -n "${OSS_READINESS_ENV_FILE:-}" ] && [ -f "$OSS_READINESS_ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$OSS_READINESS_ENV_FILE"
    return 0
  fi

  # Well-known local-only candidate. Never committed; not part of any repo.
  candidate="${XDG_CONFIG_HOME:-$HOME/.config}/oss-readiness/oss-readiness.env"
  if [ -f "$candidate" ]; then
    # shellcheck source=/dev/null
    source "$candidate"
    return 0
  fi

  overlay_root="${EXTRA_OVERLAY_ROOT:-}"
  if [ -z "$overlay_root" ] && command -v chezmoi >/dev/null 2>&1; then
    overlay_root="$(chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || true)"
  fi
  if [ -n "$overlay_root" ] && [ -f "$overlay_root/oss-readiness.env" ]; then
    # shellcheck source=/dev/null
    source "$overlay_root/oss-readiness.env"
    return 0
  fi

  for candidate in \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling"/*/oss-readiness.env \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}"/*/oss-readiness.env
  do
    [ -f "$candidate" ] || continue
    if grep -qE "^OSS_READINESS_REPO=${repo}$" "$candidate" 2>/dev/null; then
      # shellcheck source=/dev/null
      source "$candidate"
      return 0
    fi
  done
  return 1
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

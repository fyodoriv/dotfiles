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

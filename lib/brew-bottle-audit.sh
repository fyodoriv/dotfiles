#!/bin/bash
# Cached Homebrew bottle signature audit.
#
# The security doctor needs to verify every executable Homebrew bottle and
# shared library. `codesign -dvv` is intentionally expensive, so this library
# caches only a successful audit. The cache is invalidated by a Cellar
# inventory change, a bounded TTL, an explicit doctor refresh, or the signing
# repair command.
#
# Callers:
#   source "$DOTFILES_DIR/lib/brew-bottle-audit.sh"
#   dotfiles_brew_bottle_audit
#
# Results are process-scoped shell variables:
#   DOTFILES_BREW_BOTTLE_AUDIT_TOTAL
#   DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED
#   DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED
#   DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT

dotfiles_brew_bottle_audit_cache_file() {
  local cache_dir
  cache_dir="${DOTFILES_BREW_BOTTLE_AUDIT_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles}"
  printf '%s\n' "$cache_dir/brew-bottle-signature-audit-v1"
}

dotfiles_brew_bottle_audit_cache_invalidate() {
  local cache_file
  cache_file="$(dotfiles_brew_bottle_audit_cache_file)"
  rm -f "$cache_file"
}

_dotfiles_brew_bottle_audit_now() {
  case "${DOTFILES_BREW_BOTTLE_AUDIT_NOW:-}" in
    *[!0-9]*|'') date +%s ;;
    *) printf '%s\n' "$DOTFILES_BREW_BOTTLE_AUDIT_NOW" ;;
  esac
}

_dotfiles_brew_bottle_audit_find_bin() {
  if [ -n "${DOTFILES_BREW_BOTTLE_AUDIT_FIND_BIN:-}" ]; then
    printf '%s\n' "$DOTFILES_BREW_BOTTLE_AUDIT_FIND_BIN"
  elif declare -f dotfiles_resolve_find >/dev/null 2>&1; then
    dotfiles_resolve_find "${DOTFILES_DIR:-}/bin"
  else
    command -v find
  fi
}

_dotfiles_brew_bottle_audit_inventory_fingerprint() {
  local find_bin stat_bin prefix
  local -a stat_args prefixes
  find_bin="$(_dotfiles_brew_bottle_audit_find_bin)" || return 1
  stat_bin="${DOTFILES_BREW_BOTTLE_AUDIT_STAT_BIN:-stat}"
  IFS=':' read -r -a prefixes <<< "${DOTFILES_BREW_BOTTLE_AUDIT_PREFIXES:-/usr/local/Cellar:/opt/homebrew/Cellar}"

  for prefix in "${prefixes[@]}"; do
    [ -d "$prefix" ] || continue
    if "$stat_bin" -f '%N:%m:%c' "$prefix" >/dev/null 2>&1; then
      stat_args=(-f '%N:%m:%c')
    else
      stat_args=(-c '%n:%Y:%Z')
    fi
    break
  done

  {
    printf 'format=1\n'
    for prefix in "${prefixes[@]}"; do
      [ -d "$prefix" ] || continue
      printf 'prefix=%s\n' "$prefix"
      "$find_bin" "$prefix" -mindepth 0 -maxdepth 2 -type d \
        -exec "$stat_bin" "${stat_args[@]}" {} + 2>/dev/null
    done
  } | LC_ALL=C sort | {
    if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 | awk '{ print $1; exit }'
    elif command -v sha256sum >/dev/null 2>&1; then
      sha256sum | awk '{ print $1; exit }'
    else
      cksum | awk '{ print $1 ":" $2; exit }'
    fi
  }
}

_dotfiles_brew_bottle_audit_cache_load() {
  local fingerprint="$1" cache_file now ttl
  local cache_version="" cache_fingerprint="" cache_created_at=""
  local cache_result="" cache_total="" key value

  [ "${DOTFILES_DOCTOR_REFRESH:-0}" = "1" ] && return 1
  cache_file="$(dotfiles_brew_bottle_audit_cache_file)"
  [ -f "$cache_file" ] || return 1

  while IFS='=' read -r key value; do
    case "$key" in
      version) cache_version="$value" ;;
      fingerprint) cache_fingerprint="$value" ;;
      created_at) cache_created_at="$value" ;;
      result) cache_result="$value" ;;
      total) cache_total="$value" ;;
    esac
  done < "$cache_file"

  [[ "$cache_version" = "1" ]] || return 1
  [[ "$cache_fingerprint" = "$fingerprint" ]] || return 1
  [[ "$cache_result" = "pass" ]] || return 1
  [[ "$cache_created_at" =~ ^[0-9]+$ ]] || return 1
  [[ "$cache_total" =~ ^[0-9]+$ ]] || return 1

  now="$(_dotfiles_brew_bottle_audit_now)"
  ttl="${DOTFILES_BREW_BOTTLE_AUDIT_CACHE_TTL_SECONDS:-86400}"
  [[ "$ttl" =~ ^[0-9]+$ ]] || ttl=86400
  [ "$now" -ge "$cache_created_at" ] || return 1
  [ $((now - cache_created_at)) -le "$ttl" ] || return 1

  DOTFILES_BREW_BOTTLE_AUDIT_TOTAL="$cache_total"
  DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED=0
  DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED=0
  # shellcheck disable=SC2034 # Consumed by the security doctor after this function returns.
  DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT=1
  return 0
}

_dotfiles_brew_bottle_audit_cache_store() {
  local fingerprint="$1" total="$2" cache_file cache_dir temporary now
  [ "$total" -gt 0 ] || return 0

  cache_file="$(dotfiles_brew_bottle_audit_cache_file)"
  cache_dir="$(dirname "$cache_file")"
  mkdir -p "$cache_dir" || return 0
  temporary="$(mktemp "$cache_dir/.brew-bottle-signature-audit.XXXXXX")" || return 0
  now="$(_dotfiles_brew_bottle_audit_now)"

  (
    umask 077
    printf 'version=1\n'
    printf 'fingerprint=%s\n' "$fingerprint"
    printf 'created_at=%s\n' "$now"
    printf 'result=pass\n'
    printf 'total=%s\n' "$total"
  ) > "$temporary" && mv -f "$temporary" "$cache_file" || rm -f "$temporary"
}

_dotfiles_brew_bottle_audit_candidate() {
  local candidate="$1" file_bin="$2" codesign_bin="$3" file_type signature status=0
  file_type="$("$file_bin" -b "$candidate" 2>/dev/null || true)"
  case "$file_type" in
    Mach-O*) ;;
    *) return 0 ;;
  esac

  DOTFILES_BREW_BOTTLE_AUDIT_TOTAL=$((DOTFILES_BREW_BOTTLE_AUDIT_TOTAL + 1))
  signature="$("$codesign_bin" -dvv "$candidate" 2>&1)" || status=$?
  [ "$status" -eq 0 ] && return 0
  case "$signature" in
    *"not signed"*)
      DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED=$((DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED + 1))
      ;;
    *"Signature="*) ;;
    *)
      DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED=$((DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED + 1))
      ;;
  esac
}

_dotfiles_brew_bottle_audit_executable_files() {
  local find_bin="$1" prefix="$2"

  # GNU find uses /mode while BSD find uses +mode. Probe the parser first,
  # then fall back to all regular files and let the caller test -x.
  if "$find_bin" "$prefix" -maxdepth 0 -perm /111 >/dev/null 2>&1; then
    "$find_bin" "$prefix" -maxdepth 5 -type f -perm /111 2>/dev/null
  elif "$find_bin" "$prefix" -maxdepth 0 -perm +111 >/dev/null 2>&1; then
    "$find_bin" "$prefix" -maxdepth 5 -type f -perm +111 2>/dev/null
  else
    "$find_bin" "$prefix" -maxdepth 5 -type f 2>/dev/null
  fi
}

dotfiles_brew_bottle_audit() {
  local fingerprint find_bin file_bin codesign_bin prefix candidate
  local -a prefixes

  DOTFILES_BREW_BOTTLE_AUDIT_TOTAL=0
  DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED=0
  DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED=0
  # shellcheck disable=SC2034 # Consumed by the security doctor after this function returns.
  DOTFILES_BREW_BOTTLE_AUDIT_CACHE_HIT=0

  fingerprint="$(_dotfiles_brew_bottle_audit_inventory_fingerprint)" || return 0
  _dotfiles_brew_bottle_audit_cache_load "$fingerprint" && return 0

  find_bin="$(_dotfiles_brew_bottle_audit_find_bin)" || return 0
  file_bin="${DOTFILES_BREW_BOTTLE_AUDIT_FILE_BIN:-/usr/bin/file}"
  codesign_bin="${DOTFILES_BREW_BOTTLE_AUDIT_CODESIGN_BIN:-$(command -v codesign 2>/dev/null || true)}"
  [ -x "$file_bin" ] || return 0
  [ -n "$codesign_bin" ] || return 0
  IFS=':' read -r -a prefixes <<< "${DOTFILES_BREW_BOTTLE_AUDIT_PREFIXES:-/usr/local/Cellar:/opt/homebrew/Cellar}"

  for prefix in "${prefixes[@]}"; do
    [ -d "$prefix" ] || continue
    while IFS= read -r candidate; do
      [ -x "$candidate" ] || continue
      _dotfiles_brew_bottle_audit_candidate "$candidate" "$file_bin" "$codesign_bin"
    done < <(_dotfiles_brew_bottle_audit_executable_files "$find_bin" "$prefix")
    while IFS= read -r candidate; do
      [ -x "$candidate" ] && continue
      _dotfiles_brew_bottle_audit_candidate "$candidate" "$file_bin" "$codesign_bin"
    done < <("$find_bin" "$prefix" -maxdepth 6 -type f \( -name '*.dylib' -o -name '*.so' \) 2>/dev/null)
  done

  if [ "$DOTFILES_BREW_BOTTLE_AUDIT_UNSIGNED" -eq 0 ] \
      && [ "$DOTFILES_BREW_BOTTLE_AUDIT_UNVERIFIED" -eq 0 ]; then
    _dotfiles_brew_bottle_audit_cache_store "$fingerprint" "$DOTFILES_BREW_BOTTLE_AUDIT_TOTAL"
  else
    dotfiles_brew_bottle_audit_cache_invalidate
  fi
}

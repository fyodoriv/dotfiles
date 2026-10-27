#!/bin/bash
# Blocks full test suites and builds that do not run through heavy-run (#357).
# Receives Claude Code PreToolUse tool input as JSON on stdin.
# Single-file runs stay allowed, so fast iteration stays fast.
# HEAVY_RUN_HOOK=off turns the hook off.

set -euo pipefail
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

[ "${HEAVY_RUN_HOOK:-on}" = off ] && exit 0

input=$(cat)
command="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
[ -n "$command" ] || exit 0

# True when an argument names one file (a path or a dotted file name).
_has_file_arg() {
  local a
  for a in "$@"; do
    case "$a" in -*|run|test) continue ;; esac
    case "$a" in */*|*.*) return 0 ;; esac
  done
  return 1
}

# True when the script name is a test or build script.
_heavy_script() {
  case "$1" in test|test:*|test-*|t|build) return 0 ;; esac
  return 1
}

# True when one simple command (no && ; |) is a heavy run.
_is_heavy() {
  local -a w
  read -r -a w <<< "$1" || true
  while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == *=* ]]; do w=("${w[@]:1}"); done
  [ "${#w[@]}" -gt 0 ] || return 1
  [ "${w[0]}" = npx ] && w=("${w[@]:1}")
  [ "${#w[@]}" -gt 0 ] || return 1
  local tool="${w[0]}" a
  local -a rest=("${w[@]:1}")
  case "$tool" in
    npm|yarn|pnpm)
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in -*|run|run-script) continue ;; esac
        _heavy_script "$a" && return 0
        return 1
      done
      return 1 ;;
    vitest|jest)
      _has_file_arg ${rest[@]+"${rest[@]}"} && return 1
      return 0 ;;
    playwright)
      [ "${rest[0]:-}" = test ] && return 0
      return 1 ;;
    bats)
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in *.bats) return 1 ;; esac
      done
      return 0 ;;
  esac
  return 1
}

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  case "$seg" in heavy-run|heavy-run\ *) continue ;; esac
  if _is_heavy "$seg"; then
    echo "BLOCKED: a full test suite or build must queue on the Mac-wide lock. Run this as \`heavy-run <command>\`." >&2
    exit 2
  fi
done < <(printf '%s\n' "$command" | sed -E 's/(&&|\|\||;|\|)/\n/g')

exit 0

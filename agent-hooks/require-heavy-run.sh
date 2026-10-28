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

# True when the arguments pick one test: a grep filter with a real value, or
# an explicit spec path. "." , ".*", a folder ("tests/"), and the value of
# --config, -c, or --project do not count.
_one_test_args() {
  local a v
  while [ $# -gt 0 ]; do
    a="$1"; shift
    case "$a" in
      --config|-c|--project) shift || true ;;
      -g|--grep)
        v="${1:-}"
        case "$v" in ""|-*|.|".*") ;; *) return 0 ;; esac
        case "$v" in -*) ;; *) shift || true ;; esac ;;
      -g=*|--grep=*)
        v="${a#*=}"
        case "$v" in ""|.|".*") ;; *) return 0 ;; esac ;;
      -*|run|test|.|..|./|*/) ;;
      */*|*.*) return 0 ;;
    esac
  done
  return 1
}

# True when the script name is a test or build script.
_heavy_script() {
  case "$1" in test|test:*|test-*|t|build|e2e|e2e:*|e2e-*|ui|ui:*|ui-*) return 0 ;; esac
  return 1
}

# True when the words after an exec-style runner start a Playwright test run.
_playwright_test_run() {
  [ "${1:-}" = playwright ] && [ "${2:-}" = test ]
}

# True when one simple command (no && ; |) is a heavy run.
_is_heavy() {
  local -a w
  read -r -a w <<< "$1" || true
  # Strip VAR=x and the prefixes time, command, exec, nohup, timeout N, env,
  # nice [-n N], caffeinate [-flags].
  while [ "${#w[@]}" -gt 0 ]; do
    case "${w[0]}" in
      *=*|time|command|exec|nohup) w=("${w[@]:1}") ;;
      timeout)
        w=("${w[@]:1}")
        while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* ]]; do w=("${w[@]:1}"); done
        w=("${w[@]:1}") ;;
      env|caffeinate)
        w=("${w[@]:1}")
        while [ "${#w[@]}" -gt 0 ] && [[ "${w[0]}" == -* || "${w[0]}" == *=* ]]; do w=("${w[@]:1}"); done ;;
      nice)
        w=("${w[@]:1}")
        if [ "${w[0]:-}" = -n ]; then w=("${w[@]:2}")
        elif [[ "${w[0]:-}" == -[0-9]* ]]; then w=("${w[@]:1}"); fi ;;
      *) break ;;
    esac
  done
  [ "${#w[@]}" -gt 0 ] || return 1
  [ "${w[0]}" = heavy-run ] && return 1
  case "${w[0]}" in npx|bunx) w=("${w[@]:1}") ;; esac
  [ "${#w[@]}" -gt 0 ] || return 1
  local tool="${w[0]}" a
  local -a rest=() raw=("${w[@]:1}")
  local i=0
  # Drop workspace selectors (and their value) so `pnpm --filter web e2e` reads as `pnpm e2e`.
  while [ "$i" -lt "${#raw[@]}" ]; do
    case "${raw[$i]}" in
      --filter|-F|--workspace|-w|--prefix|-C) i=$((i + 2)); continue ;;
    esac
    rest+=("${raw[$i]}"); i=$((i + 1))
  done
  case "$tool" in
    npm|yarn|pnpm)
      # npm exec / pnpm exec / pnpm dlx / yarn playwright test
      case "${rest[0]:-}" in
        exec|dlx)
          _playwright_test_run "${rest[1]:-}" "${rest[2]:-}" && ! _one_test_args "${rest[@]:3}" && return 0
          return 1 ;;
      esac
      if _playwright_test_run "${rest[0]:-}" "${rest[1]:-}"; then
        _one_test_args "${rest[@]:2}" && return 1
        return 0
      fi
      for i in "${!rest[@]}"; do
        a="${rest[$i]}"
        case "$a" in -*|run|run-script) continue ;; esac
        _heavy_script "$a" || return 1
        _one_test_args "${rest[@]:$((i + 1))}" && return 1
        return 0
      done
      return 1 ;;
    vitest|jest)
      _has_file_arg ${rest[@]+"${rest[@]}"} && return 1
      return 0 ;;
    make)
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in -n|--dry-run|--just-print|--recon) return 1 ;; esac
      done
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in e2e|test-all|test-force) return 0 ;; esac
      done
      return 1 ;;
    playwright)
      if [ "${rest[0]:-}" = test ]; then
        _one_test_args "${rest[@]:1}" && return 1
        return 0
      fi
      return 1 ;;
    bats)
      for a in ${rest[@]+"${rest[@]}"}; do
        case "$a" in *.bats) return 1 ;; esac
      done
      return 0 ;;
  esac
  return 1
}

# Remove heredoc bodies, then replace each quoted string with Q (empty quotes vanish; a lone . or .* stays), so words inside commit messages and PR bodies are never matched.
_strip_text() {
  /usr/bin/perl -0777 -pe '
    s/<<-?\s*(["\x27]?)(\w+)\1([^\n]*\n)(?:.*?\n)??[ \t]*\2[ \t]*$/ $3/gms;
    s/("(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)/my $i = substr($1, 1, -1); $i =~ m{^\.\*?$} ? $i : length($i) ? "Q" : ""/gse;
  '
}

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  case "$seg" in heavy-run|heavy-run\ *) continue ;; esac
  if _is_heavy "$seg"; then
    echo "BLOCKED: a full test suite or build must queue on the Mac-wide lock. Run this as \`heavy-run <command>\`." >&2
    exit 2
  fi
done < <(printf '%s\n' "$command" | _strip_text | sed -E 's/(&&|\|\||;|\|)/\n/g')

exit 0

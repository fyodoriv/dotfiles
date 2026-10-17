#!/bin/bash
# Local errors log: one JSON line per failure, for docs/observability.md.
# Usage: source "$DOTFILES_DIR/lib/errors-log.sh"
#        log_error <story> <source> <code> [check]
#
# Every field is allow-listed, so no free text (paths, messages, names) can
# reach the log:
#   story   US01..US99            the user story the failure breaks
#   source  doctor|sync|morning   the job that failed
#   code    [a-z0-9_-]{1,40}      a short fixed failure code
#   check   [A-Za-z0-9_.-]{1,80}  an optional doctor check ID
# A value that does not match is replaced with "invalid".
#
# File: $DOTFILES_ERRORS_FILE (default ~/.local/state/dotfiles/errors.jsonl),
# trimmed to the last 2000 lines. DOTFILES_ERRORS_LOG=0 turns it off; the
# Makefile and tests/test_helper.bash set it for every test run.
# Never fails the caller.

DOTFILES_ERRORS_FILE="${DOTFILES_ERRORS_FILE:-$HOME/.local/state/dotfiles/errors.jsonl}"

_errors_allow() {
  local value="$1" pattern="$2"
  if [[ "$value" =~ $pattern ]]; then printf '%s' "$value"; else printf 'invalid'; fi
}

log_error() {
  # Off with DOTFILES_ERRORS_LOG=0, and inside a bats test unless the test
  # sets DOTFILES_ERRORS_LOG=1, so no test writes the real log.
  case "${DOTFILES_ERRORS_LOG:-}" in
    0) return 0 ;;
    1) ;;
    *) [ -n "${BATS_TEST_FILENAME:-}" ] && return 0 ;;
  esac
  local story source code check line
  story="$(_errors_allow "${1:-}" '^US[0-9]{2}$')"
  source="$(_errors_allow "${2:-}" '^(doctor|sync|morning)$')"
  code="$(_errors_allow "${3:-}" '^[a-z0-9_-]{1,40}$')"
  line="{\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"story\":\"$story\",\"source\":\"$source\",\"code\":\"$code\""
  if [ -n "${4:-}" ]; then
    check="$(_errors_allow "$4" '^[A-Za-z0-9_.-]{1,80}$')"
    line="$line,\"check\":\"$check\""
  fi
  line="$line}"
  mkdir -p "$(dirname "$DOTFILES_ERRORS_FILE")" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$DOTFILES_ERRORS_FILE" 2>/dev/null || return 0
  if [ "$(wc -l < "$DOTFILES_ERRORS_FILE" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -n 2000 "$DOTFILES_ERRORS_FILE" > "$DOTFILES_ERRORS_FILE.tmp" 2>/dev/null &&
      mv "$DOTFILES_ERRORS_FILE.tmp" "$DOTFILES_ERRORS_FILE" 2>/dev/null
  fi
  return 0
}

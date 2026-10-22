#!/bin/bash
# Ask before a hard-to-undo dotfiles command (`# confirm:` in bin/dotfiles).
# `dotfiles actions --check` looks for these calls on the code path of each
# form that needs a yes.
#
# Usage (sourced):
#   confirm_yes <yes 0|1> "<what it changes>" ["<refusal text>"]
#   confirm_gate "<what it changes>" "$@"
#   set -- ${CONFIRM_ARGS[@]+"${CONFIRM_ARGS[@]}"}
#   confirm_require_yes <yes 0|1> "<refusal text>"
#
# confirm_yes: yes=1 is the person's yes. At a terminal it asks y/N on the
# terminal itself (/dev/tty), so the question shows and the answer reads
# there even when the output goes to a log. Without a terminal it refuses
# (exit 2) and changes nothing, so an agent asks the user, then passes --yes.
# confirm_gate: reads --yes from the arguments (and removes it), lets
# --dry-run and --help through without a yes, then calls confirm_yes.
# confirm_require_yes: refuses unless yes=1, even at a terminal.
#
# CONFIRM_ARGS: the arguments without --yes, in process scope (the calling
# script's shell); each confirm_gate call resets it.

confirm_yes() {
  local yes="$1" what="$2" refusal="${3:-}" answer
  [ "$yes" = 1 ] && return 0
  if [ -t 0 ] && { : </dev/tty; } 2>/dev/null; then
    printf 'This %s.\nContinue? [y/N] ' "$what" >/dev/tty
    read -r answer </dev/tty || answer=""
    case "$answer" in y | Y | yes | YES) return 0 ;; esac
    echo "✗ Not confirmed; nothing changed." >&2
    exit 1
  fi
  if [ -n "$refusal" ]; then
    echo "✗ $refusal" >&2
  else
    echo "✗ This $what, so it needs a yes. Run it in a terminal, or pass --yes after the user agrees." >&2
  fi
  exit 2
}

confirm_gate() {
  local what="$1" yes=0 free=0 a
  shift
  CONFIRM_ARGS=()
  for a in "$@"; do
    case "$a" in
      --yes) yes=1 ;;
      --dry-run | --help | -h) free=1; CONFIRM_ARGS+=("$a") ;;
      *) CONFIRM_ARGS+=("$a") ;;
    esac
  done
  if [ "$free" -eq 1 ]; then return 0; fi
  confirm_yes "$yes" "$what"
}

confirm_require_yes() {
  [ "$1" = 1 ] && return 0
  echo "✗ $2" >&2
  exit 2
}

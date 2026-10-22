#!/bin/bash
# Ask before a hard-to-undo dotfiles command (`# confirm:` in bin/dotfiles).
#
# Usage (sourced):
#   confirm_gate "<what it changes>" "$@"
#   set -- ${CONFIRM_ARGS[@]+"${CONFIRM_ARGS[@]}"}
#
# --yes is the person's yes; it is removed from the arguments. At a terminal
# without --yes it asks y/N. Without a terminal and without --yes it refuses
# (exit 2) and changes nothing, so an agent asks the user, then passes --yes.
# --dry-run and --help need no yes.
#
# CONFIRM_ARGS: the arguments without --yes, in process scope (the calling
# script's shell); each confirm_gate call resets it.

confirm_gate() {
  local what="$1" yes=0 free=0 a answer
  shift
  CONFIRM_ARGS=()
  for a in "$@"; do
    case "$a" in
      --yes) yes=1 ;;
      --dry-run | --help | -h) free=1; CONFIRM_ARGS+=("$a") ;;
      *) CONFIRM_ARGS+=("$a") ;;
    esac
  done
  if [ "$yes" -eq 1 ] || [ "$free" -eq 1 ]; then return 0; fi
  if [ -t 0 ]; then
    printf 'This %s.\nContinue? [y/N] ' "$what" >&2
    read -r answer || answer=""
    case "$answer" in y | Y | yes | YES) return 0 ;; esac
    echo "✗ Not confirmed; nothing changed." >&2
    exit 1
  fi
  echo "✗ This $what, so it needs a yes. Run it in a terminal, or pass --yes after the user agrees." >&2
  exit 2
}

#!/bin/bash
# Recognize a literal status invocation without interpreting shell syntax.
literal_status_only() {
  local -a words
  local option command="${1-}"
  case "$command" in
    ''|*$'\n'*|*$'\r'*|*[!a-zA-Z0-9_\ =-]*) return 1 ;;
  esac
  case "$command" in *[!\ ]*) ;; *) return 1 ;; esac
  IFS=$' \t' read -r -a words <<< "$command"
  [ "${#words[@]}" -ge 2 ] || return 1
  [ "${words[0]}" = git ] && [ "${words[1]}" = status ] || return 1
  for option in "${words[@]:2}"; do
    case "$option" in
      -s|-b|--short|--branch|--long|--porcelain|--porcelain=v1|--porcelain=v2) ;;
      *) return 1 ;;
    esac
  done
  return 0
}

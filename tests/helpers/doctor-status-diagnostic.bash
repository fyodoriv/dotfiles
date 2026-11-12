doctor_status_category() {
  case "$1" in
    fixed|fail|skipped) printf '%s\n' "$1" ;;
    '') printf '%s\n' empty ;;
    *) printf '%s\n' unexpected ;;
  esac
}

doctor_require_fixed() {
  [ "$1" = fixed ] && return 0
  printf 'doctor boolean status category: %s\n' "$(doctor_status_category "$1")" >&2
  return 1
}

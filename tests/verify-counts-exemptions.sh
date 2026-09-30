# Lines that match COUNT_PATTERN but are thresholds, limits, or structural requirements — not inventory.
is_verify_counts_exemption() {
  local line="$1"
  case "$line" in
    *"file > "*" lines"*) return 0 ;;
    *registers\ ≥\ *checks*) return 0 ;;
    *"≤"*" lines"*) return 0 ;;
    *"(N checks)"*) return 0 ;;
    *"first line ≤"*) return 0 ;;
    *"missing any of the 4 checks"*) return 0 ;;
    *"N=2"*) return 0 ;;
    *">50 files"*) return 0 ;;
    *"more than 50 files"*) return 0 ;;
  esac
  return 1
}

#!/bin/bash
# Audit Brewfile template entries against Homebrew metadata without installing them.
set -euo pipefail

manifest="${1:-.chezmoiscripts/run_onchange_brew.sh.tmpl}"
metadata_timeout="${BREW_AUDIT_METADATA_TIMEOUT:-20}"
livecheck_timeout="${BREW_AUDIT_LIVECHECK_TIMEOUT:-20}"
skip_livecheck="${BREW_AUDIT_SKIP_LIVECHECK:-0}"

if [ ! -f "$manifest" ]; then
  echo "Brew audit manifest not found: $manifest" >&2
  exit 1
fi

validate_positive_timeout() {
  local name="$1"
  local value="$2"

  case "$value" in
    '' | *[!0-9]*)
      echo "$name must be a positive integer number of seconds" >&2
      exit 1
      ;;
  esac
  if [ "$value" -le 0 ]; then
    echo "$name must be greater than zero" >&2
    exit 1
  fi
}

validate_positive_timeout "BREW_AUDIT_METADATA_TIMEOUT" "$metadata_timeout"
validate_positive_timeout "BREW_AUDIT_LIVECHECK_TIMEOUT" "$livecheck_timeout"

for tool in brew jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Brew audit requires $tool on PATH" >&2
    exit 1
  fi
done

problems_file="$(mktemp)"
summary_file="$(mktemp)"
error_file="$(mktemp)"
trap 'rm -f "$problems_file" "$summary_file" "$error_file"' EXIT

formula_count=0
cask_count=0
manifest_entries="$(sed -nE 's/^[[:space:]]*(brew|cask)[[:space:]]+"([^"]+)".*/\1 \2/p' "$manifest" | sort -u)"

if [ -z "$manifest_entries" ]; then
  echo "Brew audit found no brew or cask entries in: $manifest" >&2
  exit 1
fi

write_output() {
  local name="$1"
  local value="$2"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s=%s\n' "$name" "$value" >> "$GITHUB_OUTPUT"
  fi
}

write_multiline_output() {
  local name="$1"
  local file="$2"
  local delimiter="BREW_AUDIT_EOF_${RANDOM}_${RANDOM}"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf '%s<<%s\n' "$name" "$delimiter" >> "$GITHUB_OUTPUT"
    cat "$file" >> "$GITHUB_OUTPUT"
    printf '%s\n' "$delimiter" >> "$GITHUB_OUTPUT"
  fi
}

append_problem() {
  local label="$1"
  local name="$2"
  local message="$3"

  printf -- '- %s `%s`: %s\n' "$label" "$name" "$message" >> "$problems_file"
}

describe_reason() {
  local state="$1"
  local date="$2"
  local reason="$3"
  local detail="$state"

  if [ -n "$date" ]; then
    detail="$detail since $date"
  fi
  if [ -n "$reason" ]; then
    detail="$detail ($reason)"
  fi

  printf '%s' "$detail"
}

run_with_timeout() {
  local seconds="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3
  local pid watcher timeout_marker status

  timeout_marker="$(mktemp)"
  "$@" >"$stdout_file" 2>"$stderr_file" &
  pid=$!
  (
    local sleep_pid
    sleep_pid=""
    trap '[ -n "${sleep_pid:-}" ] && kill "$sleep_pid" 2>/dev/null || true; exit 0' TERM INT
    sleep "$seconds" &
    sleep_pid=$!
    wait "$sleep_pid" 2>/dev/null || exit 0
    if kill -0 "$pid" 2>/dev/null; then
      printf 'timeout\n' > "$timeout_marker"
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
    fi
  ) </dev/null >/dev/null 2>&1 &
  watcher=$!

  status=0
  wait "$pid" || status=$?
  kill "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true

  if [ -s "$timeout_marker" ]; then
    rm -f "$timeout_marker"
    return 124
  fi

  rm -f "$timeout_marker"
  return "$status"
}

check_livecheck() {
  local label="$1"
  local flag="$2"
  local name="$3"
  local live_json status current latest live_output_file live_status

  if [ "$skip_livecheck" = "1" ] || [ "$skip_livecheck" = "true" ]; then
    return 0
  fi

  live_output_file="$(mktemp)"
  if run_with_timeout "$livecheck_timeout" "$live_output_file" "$error_file" env HOMEBREW_DEVELOPER=1 HOMEBREW_NO_AUTO_UPDATE=1 brew livecheck --json --quiet "$flag" "$name"; then
    live_json="$(cat "$live_output_file")"
    rm -f "$live_output_file"
  else
    live_status=$?
    rm -f "$live_output_file"
    if [ "$live_status" -eq 124 ]; then
      append_problem "$label" "$name" "livecheck timed out after ${livecheck_timeout}s; retry when network is healthy or set BREW_AUDIT_SKIP_LIVECHECK=1 for metadata-only audits"
    fi
    : > "$error_file"
    return 0
  fi

  status="$(printf '%s' "$live_json" | jq -r '.[0].status // empty')"
  current="$(printf '%s' "$live_json" | jq -r '.[0].version.current // empty')"
  latest="$(printf '%s' "$live_json" | jq -r '.[0].version.latest // empty')"

  case "$status" in
    "newer version available" | "newer versions available")
      if [ -n "$current" ] && [ -n "$latest" ]; then
        append_problem "$label" "$name" "livecheck reports upstream $latest while Homebrew metadata has $current"
      else
        append_problem "$label" "$name" "livecheck reports newer upstream versions"
      fi
      ;;
  esac
}

check_entry() {
  local manifest_kind="$1"
  local name="$2"
  local label flag selector info_json metadata primary full_name disabled disabled_date disabled_reason
  local deprecated deprecated_date deprecated_reason canonical info_output_file info_status
  local empty_marker="__brew_audit_empty__"

  case "$manifest_kind" in
    brew)
      label="formula"
      flag="--formula"
      selector='.formulae[0]'
      formula_count=$((formula_count + 1))
      ;;
    cask)
      label="cask"
      flag="--cask"
      selector='.casks[0]'
      cask_count=$((cask_count + 1))
      ;;
    *)
      append_problem "entry" "$name" "unknown Brewfile directive '$manifest_kind'"
      return 0
      ;;
  esac

  info_output_file="$(mktemp)"
  if run_with_timeout "$metadata_timeout" "$info_output_file" "$error_file" env HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 "$flag" "$name"; then
    info_json="$(cat "$info_output_file")"
    rm -f "$info_output_file"
  else
    info_status=$?
    rm -f "$info_output_file"
    if [ "$info_status" -eq 124 ]; then
      append_problem "$label" "$name" "metadata lookup timed out after ${metadata_timeout}s; retry when Homebrew is healthy or increase BREW_AUDIT_METADATA_TIMEOUT for slow runners"
    else
      append_problem "$label" "$name" "missing from Homebrew metadata ($(tr '\n' ' ' < "$error_file" | sed 's/[[:space:]]*$//'))"
    fi
    : > "$error_file"
    return 0
  fi

  metadata="$(printf '%s' "$info_json" | jq -r --arg empty "$empty_marker" "$selector |
    if . == null then
      \"__missing_json__\"
    else
      [
        (.token // .name // \$empty),
        (.full_name // \$empty),
        ((.disabled // false) | tostring),
        (.disable_date // \$empty),
        (.disable_reason // \$empty),
        ((.deprecated // false) | tostring),
        (.deprecation_date // \$empty),
        (.deprecation_reason // \$empty)
      ] | @tsv
    end")"

  if [ "$metadata" = "__missing_json__" ]; then
    append_problem "$label" "$name" "metadata response did not include a $label entry"
    return 0
  fi

  IFS=$'\t' read -r primary full_name disabled disabled_date disabled_reason deprecated deprecated_date deprecated_reason <<EOF
$metadata
EOF

  [ "$primary" = "$empty_marker" ] && primary=""
  [ "$full_name" = "$empty_marker" ] && full_name=""
  [ "$disabled_date" = "$empty_marker" ] && disabled_date=""
  [ "$disabled_reason" = "$empty_marker" ] && disabled_reason=""
  [ "$deprecated_date" = "$empty_marker" ] && deprecated_date=""
  [ "$deprecated_reason" = "$empty_marker" ] && deprecated_reason=""

  canonical="${full_name:-$primary}"
  if [ -n "$primary" ] && [ "$name" != "$primary" ] && [ "$name" != "$full_name" ]; then
    append_problem "$label" "$name" "metadata resolves to \`$canonical\`; update the Brewfile entry"
  fi

  if [ "$disabled" = "true" ]; then
    append_problem "$label" "$name" "$(describe_reason "disabled" "$disabled_date" "$disabled_reason")"
  fi

  if [ "$deprecated" = "true" ]; then
    append_problem "$label" "$name" "$(describe_reason "deprecated" "$deprecated_date" "$deprecated_reason")"
  fi

  check_livecheck "$label" "$flag" "$name"
}

while IFS=' ' read -r kind name; do
  [ -n "${kind:-}" ] || continue
  [ -n "${name:-}" ] || continue
  check_entry "$kind" "$name"
done <<EOF
$manifest_entries
EOF

problem_count="$(grep -c '^- ' "$problems_file" 2>/dev/null || true)"

{
  printf 'Checked %s formulae and %s casks from `%s`.\n\n' "$formula_count" "$cask_count" "$manifest"
  printf 'Metadata timeout: %ss per entry with HOMEBREW_NO_AUTO_UPDATE=1.\n' "$metadata_timeout"
  if [ "$skip_livecheck" = "1" ] || [ "$skip_livecheck" = "true" ]; then
    echo "Livecheck skipped because BREW_AUDIT_SKIP_LIVECHECK=$skip_livecheck; metadata checks still ran."
    echo
  else
    printf 'Livecheck timeout: %ss per entry. Set BREW_AUDIT_SKIP_LIVECHECK=1 for metadata-only audits.\n\n' "$livecheck_timeout"
  fi
  if [ "$problem_count" -gt 0 ]; then
    echo "The following Brewfile entries need attention:"
    echo
    cat "$problems_file"
  else
    echo "All Brewfile entries resolved in Homebrew metadata with no disabled, deprecated, renamed, or livecheck update signals."
  fi
} > "$summary_file"

if [ "$problem_count" -gt 0 ]; then
  write_output "found" "true"
else
  write_output "found" "false"
fi
write_multiline_output "list" "$problems_file"
write_multiline_output "summary" "$summary_file"

cat "$summary_file"

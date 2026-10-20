#!/bin/bash
# Opt-in weekly aggregate metrics file (issue #235).
#
# Writes ~/.local/share/dotfiles/metrics/weekly-<YYYY-Www>.json in the shared
# provider format (config/weekly-metrics.schema.json, copied from agentbrew).
# Numbers only; the strings are tool, version, week, and a random local
# machine_id. This file stays local. `agentbrew metrics share` owns the exit.
#
# Off unless the chezmoi key `weekly_metrics: true` (or
# DOTFILES_WEEKLY_METRICS=true). AGENTBREW_EVENTS=0 turns it off too.
# dotfiles-doctor calls weekly_metrics_write after each full run.

_WEEKLY_METRICS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

weekly_metrics_enabled() {
  [ "${AGENTBREW_EVENTS:-}" = "0" ] && return 1
  local on="${DOTFILES_WEEKLY_METRICS:-}"
  if [ -z "$on" ]; then
    on="$(chezmoi execute-template '{{ dig "weekly_metrics" false . }}' 2>/dev/null || echo false)"
  fi
  [ "$on" = "true" ]
}

# Random id made on this machine; shared with agentbrew when it has one.
_weekly_metrics_machine_id() {
  local dir="$1" id file
  for file in "$HOME/.local/share/agentbrew/metrics/machine-id" "$dir/machine-id"; do
    [ -f "$file" ] || continue
    id="$(tr -d '[:space:]' < "$file")"
    if [[ "$id" =~ ^[0-9a-f]{32}$ ]]; then
      printf '%s' "$id"
      return 0
    fi
  done
  id="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  (umask 077 && printf '%s\n' "$id" > "$dir/machine-id")
  printf '%s' "$id"
}

# Count com.dotfiles.* LaunchAgents whose last exit status is not 0.
_weekly_metrics_failed_agents() {
  local list_cmd="${DOTFILES_LAUNCHCTL_LIST_CMD:-launchctl list}"
  { eval "$list_cmd" 2>/dev/null || true; } |
    awk '$3 ~ /^com\.dotfiles\./ && $2 != "0" && $2 != "-" { n++ } END { print n + 0 }'
}

# weekly_metrics_write <pass> <fail> <fixed> <warn> <skip>
# Never fails the caller.
weekly_metrics_write() {
  weekly_metrics_enabled || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local pass="${1:-0}" fail="${2:-0}" fixed="${3:-0}" warn="${4:-0}" skip="${5:-0}"
  local dir="$HOME/.local/share/dotfiles/metrics"
  mkdir -p "$dir" 2>/dev/null || return 0
  local week id version since stats="${DOTFILES_STATS_FILE:-$HOME/.dotfiles-stats.jsonl}" failed
  week="$(date -u +%G-W%V)"
  id="$(_weekly_metrics_machine_id "$dir")"
  version="$(git -C "$_WEEKLY_METRICS_LIB_DIR/.." rev-parse --short HEAD 2>/dev/null || echo 0.0.0)"
  [[ "$version" =~ ^[0-9A-Za-z.+-]{1,40}$ ]] || version="0.0.0"
  since="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ)"
  failed="$(_weekly_metrics_failed_agents)"
  [ -f "$stats" ] || stats=/dev/null
  local tmp="$dir/weekly-$week.json.tmp"
  if jq -n --slurpfile rows <(jq -c --arg since "$since" 'select((.timestamp // "") >= $since)' "$stats" 2>/dev/null) \
    --arg tool dotfiles --arg version "$version" --arg week "$week" --arg id "$id" \
    --argjson pass "$pass" --argjson total "$((pass + fail + fixed + warn + skip))" --argjson failed "$failed" '
    def runs(t): [$rows[] | select(.task == t)];
    {tool: $tool, version: $version, week: $week, machine_id: $id,
     metrics: {
       doctor_checks_passed: $pass,
       doctor_checks_total: $total,
       doctor_runs: (runs("doctor") | length),
       heal_fixes_applied: (runs("doctor") | map(.fixed // 0) | add // 0),
       sync_runs: (runs("sync") | length),
       upgrade_runs: (runs("upgrade") | length),
       launchagent_failed: $failed
     }}' > "$tmp" 2>/dev/null; then
    mv "$tmp" "$dir/weekly-$week.json"
  else
    rm -f "$tmp"
  fi
  return 0
}

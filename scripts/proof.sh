#!/bin/bash
# proof.sh — measure what the README claims and write its Proof section.
#
# Usage:
#   scripts/proof.sh                 # collect from this Mac, save docs/proof/metrics.json, rewrite README
#   scripts/proof.sh --collect FILE  # aggregate the stats log into FILE (no shell timing, no README)
#   scripts/proof.sh --render        # print the README Proof section from docs/proof/metrics.json
#   scripts/proof.sh --validate FILE # fail when a metric has no value, unit, date, kind, or command
#
# Field data is the local, content-free stats log (~/.dotfiles-stats.jsonl,
# lib/stats.sh): task name, time, estimated seconds saved, units, and the
# doctor's failure count. This script uploads nothing. The machine label is a salted
# hash; the salt stays in ${XDG_STATE_HOME:-~/.local/state}/dotfiles/proof-salt.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
METRICS="${PROOF_METRICS:-$ROOT/docs/proof/metrics.json}"
README="$ROOT/README.md"
STATS="${DOTFILES_STATS_FILE:-$HOME/.dotfiles-stats.jsonl}"
CMD="scripts/proof.sh"

machine_label() {
  local salt_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/proof-salt"
  if [ ! -s "$salt_file" ]; then
    mkdir -p "$(dirname "$salt_file")"
    (umask 077 && od -An -tx1 -N16 /dev/urandom | tr -d ' \n' >"$salt_file")
  fi
  printf 'm-%s' "$(printf '%s:%s' "$(cat "$salt_file")" "$(hostname)" | shasum -a 256 | cut -c1-10)"
}

# Median of 5 interactive zsh starts, in ms (engineering health, not field data).
shell_ms() {
  local _
  for _ in 1 2 3 4 5; do
    /usr/bin/time -p zsh -i -c exit 2>&1 >/dev/null | awk '/^real/{print int($2*1000)}'
  done | sort -n | sed -n 3p
}

validate() {
  jq -e '
    (.metrics | length > 0) and
    ([.metrics | to_entries[] | select(
        (.value.value == null) or (.value.unit // "") == "" or (.value.date // "") == "" or
        (.value.kind // "") == "" or (.value.command // "") == "")] | length == 0)
  ' "$1" >/dev/null || {
    jq -r '.metrics | to_entries[] | . as $m | ["value","unit","date","kind","command"][]
      | select(($m.value[.] // "") == "") | "proof: metric \($m.key) has no \(.)"' "$1" 2>/dev/null
    echo "proof: $1 failed the check (each metric needs value, unit, date, kind, command)" >&2
    return 1
  }
}

collect() {
  local out="$1" shell="${2:-}" label today prev="{}"
  label="$(machine_label)"
  today="$(date -u +%F)"
  [ -f "$out" ] && prev="$(cat "$out")"
  [ -f "$STATS" ] || { echo "proof: no stats log at $STATS" >&2; return 1; }
  jq -s --arg label "$label" --arg today "$today" --arg cmd "$CMD" \
    --arg shell "$shell" --arg arch "$(uname -s | tr '[:upper:]' '[:lower:]') $(uname -m)" \
    --argjson prev "$prev" '
    def since(d): (now - d * 86400 | todate) as $s | map(select(.timestamp >= $s));
    def range: if length == 0 then "none" else "\(.[0].timestamp[0:10]) to \(.[-1].timestamp[0:10])" end;
    def m($v; $unit; $detail; $kind; $name):
      { value: $v, unit: $unit, date: $today, kind: $kind, command: $cmd, detail: $detail,
        history: ((($prev.metrics[$name].history // []) | map(select(.date != $today))) + [{date: $today, value: $v}]) };
    # cursor-priority is the old name of app-priority (renamed 2026-10-20).
    map(select(type == "object" and (.timestamp | type) == "string")
      | if .task == "cursor-priority" then .task = "app-priority" else . end)
    | sort_by(.timestamp) as $all
    # Only known task names reach the chart; any other name counts as "other".
    | ["sync","doctor","audit","cleanup","git-maintain","app-priority","morning","upgrade","pr","hotfix","review","dotfiles-agent-keepawake","install"] as $known
    | ($all | since(30)) as $m30
    | ($all | since(7)) as $m7
    | ([$all[] | select(.task == "doctor" and .fail != null)] | .[-30:]) as $doc
    | ([$all[] | select(.task == "install")]) as $inst
    | ([$inst[] | select(.ok == true and .fail == 0 and (.duration_ms | type) == "number")]) as $clean
    | ([$m30[] | select(.task == "sync")]) as $sync
    | ([$m7[] | select(.task == "morning")] | unique_by(.timestamp[0:10])) as $morning
    | (($m30 | map(.seconds_saved // 0) | add // 0) / 60 | floor) as $saved
    | ("local run, \($today), \($label) (\($arch))") as $local
    | {
        metrics: ({
          doctor_clean_pct: m(
            (if ($doc | length) == 0 then null else (($doc | map(select(.fail == 0)) | length) * 100 / ($doc | length) | floor) end);
            "%"; "last \($doc | length) doctor runs, \($doc | range); a run is clean when no check fails";
            "real use"; "doctor_clean_pct"),
          doctor_fail_median: m(
            (if ($doc | length) == 0 then null else ($doc | map(.fail) | sort | .[length / 2 | floor]) end);
            "failing check(s)"; "median per doctor run, max \($doc | map(.fail) | max), last \($doc | length) runs";
            "real use"; "doctor_fail_median"),
          minutes_saved_30d: m($saved; "min";
            "estimated: per-run estimates in lib/stats.sh times \($m30 | length) automation runs, \($m30 | range)";
            "real use"; "minutes_saved_30d"),
          sync_runs_30d: m(($sync | length); "runs"; "background syncs, \($sync | range)";
            "real use"; "sync_runs_30d"),
          morning_runs_7d: m(($morning | length); "days"; "days with a morning run, \($morning | range)";
            "real use"; "morning_runs_7d"),
          install_clean_minutes: m(
            (if ($clean | length) == 0 then null else ($clean | map(.duration_ms) | sort | .[length / 2 | floor] / 6000 | round / 10) end);
            "min"; "median run time of \($clean | length) of \($inst | length) install runs that ended with a clean doctor, \($inst | range)";
            "real use"; "install_clean_minutes")
        } + (if $shell == "" then {} else {
          shell_startup_ms: m(($shell | tonumber); "ms"; "median of 5 interactive zsh starts";
            $local; "shell_startup_ms") } end)
        | with_entries(select(.value.value != null))),
        charts: {
          minutes_saved_by_month: ([$all[] | select(.timestamp >= (now - 183 * 86400 | todate))]
            | group_by(.timestamp[0:7]) | map({month: .[0].timestamp[0:7], minutes: ((map(.seconds_saved // 0) | add) / 60 | floor)})),
          runs_by_task_30d: ($m30 | map(if (.task | IN($known[])) then . else .task = "other" end) | group_by(.task) | map({task: .[0].task, runs: length}) | sort_by(-.runs))
        },
        machines: (($prev.machines // {}) + { ($label): {
          date: $today, runs_30d: ($m30 | length), doctor_runs: ($doc | length),
          first_event: (($all[0].timestamp // "")[0:10]) } })
      }
  ' "$STATS" >"$out.tmp"
  mv "$out.tmp" "$out"
  validate "$out"
}

render() {
  jq -r '
    def fmt(n): (n | tostring | if test("^[0-9]{4,}$") then (explode | reverse | [recurse(if length > 3 then .[3:] else empty end) | .[0:3] | reverse | implode] | reverse | join(",")) else . end);
    def res(k): .metrics[k] as $x | if $x == null then "not measured yet" else "\(fmt($x.value)) \($x.unit) (\($x.detail))" end;
    def src(k): .metrics[k] as $x | if $x == null then "not measured yet" else "`docs/proof/metrics.json`, \($x.kind)" end;
    . as $f
    | "<!-- proof:start -->",
      "Every number below comes from `docs/proof/metrics.json`. `scripts/proof.sh` writes that file and this section.",
      "Headline rows are field outcomes. `real use` numbers come from the local, content-free stats log that each real automation run writes (`~/.dotfiles-stats.jsonl`, see [observability](docs/observability.md)).",
      "",
      "Each machine aggregates its own log here. Opt-in telemetry (`dotfiles telemetry`, off until the owner sets a key) can send the same content-free counts to PostHog EU; this section does not read them yet.",
      "",
      "| Claim | Theory | Metric | Result | Source |",
      "|---|---|---|---|---|",
      "| Self-healing: the doctor detects drift | A check that runs on a schedule catches drift before a person notices it (Forsgren, Humble, Kim 2018, *Accelerate*: fast feedback) | doctor runs with no failing check, last 30 runs | \($f | res("doctor_clean_pct")) | \($f | src("doctor_clean_pct")) |",
      "| Self-healing: what the doctor still finds | The failures per run show how much drift is left for `--fix` or a person; this row shows drift found, not drift healed | failing checks per doctor run | \($f | res("doctor_fail_median")) | \($f | src("doctor_fail_median")) |",
      "| Automation saves time | Time saved is the outcome automation promises; each task has a per-run estimate | minutes saved by automation, last 30 days | \($f | res("minutes_saved_30d")) | \($f | src("minutes_saved_30d")) |",
      "| The Mac stays in step with the source by itself | A sync that runs every 30 minutes keeps drift small | background syncs, last 30 days | \($f | res("sync_runs_30d")) | \($f | src("sync_runs_30d")) |",
      "| The morning routine gets used | A habit tool only helps when it runs most days | days with a `morning` run, last 7 days | \($f | res("morning_runs_7d")) | \($f | src("morning_runs_7d")) |",
      "| One command sets up a Mac | Time to a clean doctor is the outcome a one-step install promises | install runs and their minutes to a clean doctor | \($f | res("install_clean_minutes")) | \($f | src("install_clean_minutes")) |",
      "| The shell starts fast | Under 100 ms feels instant (Nielsen 1993, response-time limits) | shell start time on real machines | not measured yet (task `proof-shell-start-field` in TASKS.md) | not measured yet |",
      "",
      "Field data comes from \($f.machines | length) machine(s), each named by a salted hash: \([$f.machines | to_entries[] | "`\(.key)` (\(fmt(.value.runs_30d)) runs in 30 days, \(.value.doctor_runs) doctor runs, log since \(.value.first_event), as of \(.value.date))"] | join("; "))." ,
      "",
      "Engineering health (a local run, not field proof):",
      "",
      (if $f.metrics.shell_startup_ms then "- interactive shell start: \($f.metrics.shell_startup_ms.value) ms (\($f.metrics.shell_startup_ms.detail)); \($f.metrics.shell_startup_ms.kind)" else "- interactive shell start: not measured yet" end),
      "",
      "Minutes saved by automation per month (real use):",
      "",
      "```mermaid",
      "xychart-beta",
      "  title \"Minutes saved per month\"",
      "  x-axis [\($f.charts.minutes_saved_by_month | map("\"" + .month + "\"") | join(", "))]",
      "  y-axis \"minutes\"",
      "  bar [\($f.charts.minutes_saved_by_month | map(.minutes | tostring) | join(", "))]",
      "```",
      "",
      "May 2026 is high because the app-priority task then counted 15 s per run; its estimate is 0 now.",
      "",
      "Automation runs by task, last 30 days (real use). `app-priority` runs every minute and saves no time.",
      "",
      "```mermaid",
      "pie title Automation runs by task, last 30 days",
      ($f.charts.runs_by_task_30d[] | "  \"\(.task)\" : \(.runs)"),
      "```",
      "<!-- proof:end -->"
  ' "$METRICS"
}

write_readme() {
  local section tmp
  if ! grep -q '<!-- proof:start -->' "$README" || ! grep -q '<!-- proof:end -->' "$README"; then
    echo "proof: README needs both proof markers" >&2
    return 1
  fi
  section="$(render)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/proof-readme.XXXXXX")"
  SECTION="$section" awk '
    /<!-- proof:start -->/ { print ENVIRON["SECTION"]; skip = 1; next }
    /<!-- proof:end -->/ { skip = 0; next }
    !skip { print }
  ' "$README" >"$tmp"
  cat "$tmp" >"$README"
  rm -f "$tmp"
}

case "${1:-}" in
  --render) render ;;
  --validate) validate "${2:?usage: proof.sh --validate FILE}" ;;
  --collect) collect "${2:?usage: proof.sh --collect FILE}" ;;
  --help | -h) sed -n '2,/^$/s/^# \{0,1\}//p' "$0" ;;
  "")
    mkdir -p "$(dirname "$METRICS")"
    collect "$METRICS" "$(shell_ms)"
    write_readme
    echo "proof: wrote docs/proof/metrics.json and the README Proof section"
    ;;
  *) echo "proof: unknown argument $1 (see --help)" >&2; exit 2 ;;
esac

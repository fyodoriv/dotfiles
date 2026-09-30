#!/usr/bin/env bash
# Walk TASKS.md and fail when P0 or P1 entries lack any
# of the 5 rule-9 / Hypothesis-Driven-Development fields:
#
#   **Hypothesis**, **Success**, **Pivot**, **Measurement**, **Anchor**
#
# Rule-9 (per `agentbrew/templates/AGENTS.md` § "Stability Is P0" + Minsky
# `vision.md` § 9 "Pre-registered hypothesis-driven development") makes
# these 5 fields mandatory on P0/P1 tasks.
#
# Stubs for tests (no network / repo dependency):
#   TASKS_RULE9_FILE — override the TASKS.md path (default: $DOTFILES_DIR/TASKS.md)
#
# Exit semantics:
#   0 — compliant or skipped because TASKS.md is missing.
#   1 — at least one P0/P1 task lacks a required rule-9 field.
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TASKS_FILE="${TASKS_RULE9_FILE:-$DOTFILES_DIR/TASKS.md}"

if [ ! -f "$TASKS_FILE" ]; then
  echo "↷ tasks-rule9 check skipped: $TASKS_FILE not found" >&2
  exit 0
fi

# Walk the file with awk: track which `## P<N>` section we are in, find
# every `- [ ] ...` task, capture its `**ID**:` line, then check the
# block (until the next task or section boundary) for each of the 5
# required rule-9 fields — Hypothesis / Success / Pivot / Measurement /
# Anchor. Emit a failure per non-compliant task. The Minsky `pickHostTask`
# parser uses the same line shape, so this lint is structurally identical
# to the runtime check.
failures="$(
awk '
  function field_has_value(line) {
    value = line
    sub(/^  -? *\*\*[^*]+\*\*: */, "", value)
    gsub(/^ +| +$/, "", value)
    return value != ""
  }
  function reset_task() {
    in_task = 0
    task_id = ""
    has_hypothesis = 0; has_success = 0; has_pivot = 0
    has_measurement = 0; has_anchor = 0
  }
  function emit_failure() {
    if (!in_task) return
    if (priority != "P0" && priority != "P1") return
    missing = ""
    if (!has_hypothesis)  missing = missing " Hypothesis"
    if (!has_success)     missing = missing " Success"
    if (!has_pivot)       missing = missing " Pivot"
    if (!has_measurement) missing = missing " Measurement"
    if (!has_anchor)      missing = missing " Anchor"
    if (missing != "") {
      printf("rule-9-fail: %s %s missing:%s\n", priority, task_id, missing)
      non_compliant++
    }
    total++
  }
  BEGIN {
    priority = ""; in_task = 0; task_id = ""
    has_hypothesis = 0; has_success = 0; has_pivot = 0
    has_measurement = 0; has_anchor = 0
    non_compliant = 0; total = 0
  }
  # Match `## P0` / `## P1` / `## P2` / `## P3` exactly (or followed by space).
  # awk regex does NOT support `\b` word-boundary; we anchor explicitly so
  # `## P3a` (a future sub-priority) would not accidentally count as P3.
  /^## P[0-3]( |$)/ {
    emit_failure(); reset_task()
    priority = substr($0, 4, 2)
    next
  }
  /^- \[ \]/ {
    emit_failure(); reset_task()
    in_task = 1
    next
  }
  /^- \[x\]/ { emit_failure(); reset_task(); next }
  /^  -? *\*\*ID\*\*:/ {
    n = split($0, parts, ":")
    task_id = parts[2]
    gsub(/^ +| +$/, "", task_id)
    next
  }
  /^  -? *\*\*Hypothesis\*\*:/  { if (field_has_value($0)) has_hypothesis = 1; next }
  /^  -? *\*\*Success\*\*:/     { if (field_has_value($0)) has_success = 1; next }
  /^  -? *\*\*Pivot\*\*:/       { if (field_has_value($0)) has_pivot = 1; next }
  /^  -? *\*\*Measurement\*\*:/ { if (field_has_value($0)) has_measurement = 1; next }
  /^  -? *\*\*Anchor\*\*:/      { if (field_has_value($0)) has_anchor = 1; next }
  END {
    emit_failure()
    printf("rule-9-summary: total=%d non_compliant=%d\n", total, non_compliant) > "/dev/stderr"
  }
' "$TASKS_FILE"
)"

if [ -n "$failures" ]; then
  echo "$failures" >&2
  exit 1
fi

exit 0

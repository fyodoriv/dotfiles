#!/bin/bash
# Shared output helpers for check/audit scripts.
# Provides mode-aware pass/fail/fixed/skipped/warn with automatic counting.
#
# Before sourcing, set any combination of:
#   REPORT_MODE=true   — markdown output (for dotfiles audit --report)
#   QUIET_MODE=true    — suppress individual results (summary only)
#
# Public functions:
#   pass(desc)       — prints green check, increments pass_count
#   fail(desc)       — prints red X, increments fail_count, appends to report_failures[]
#   fixed(desc)      — prints lightning bolt, increments fix_count
#   skipped(desc)    — prints dim circle, increments skip_count
#   audit_warn(desc) — prints yellow warning, increments warn_count
#
# Side effects:
#   Each function increments its corresponding counter (pass_count, fail_count, etc.).
#   fail() also appends the description to report_failures[] for summary reporting.
#   Output format depends on REPORT_MODE (markdown) and QUIET_MODE (silent).
#
# Counters (read by sourcing scripts for summary output):
#   pass_count, fail_count, fix_count, skip_count, warn_count, report_failures[]
#
# Usage: source "$DOTFILES_DIR/lib/output.sh"
# shellcheck disable=SC2034  # counters used by sourcing scripts

# Ensure colors are loaded
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=colors.sh
source "$DOTFILES_DIR/lib/colors.sh"

# Counters — sourcing scripts read these for summaries
pass_count=0
fail_count=0
fix_count=0
skip_count=0
warn_count=0
report_failures=()

REPORT_MODE="${REPORT_MODE:-false}"
QUIET_MODE="${QUIET_MODE:-false}"

pass() {
  if $QUIET_MODE; then :
  elif $REPORT_MODE; then echo "- ✅ $1"
  else echo -e "  ${GREEN}✓${NC} $1"; fi
  pass_count=$((pass_count + 1))
}

fail() {
  if $QUIET_MODE; then :
  elif $REPORT_MODE; then echo "- ❌ $1"; report_failures+=("$1")
  else echo -e "  ${RED}✗${NC} $1"; fi
  fail_count=$((fail_count + 1))
}

fixed() {
  if $QUIET_MODE; then :
  elif $REPORT_MODE; then echo "- ⚡ $1 (auto-fixed)"
  else echo -e "  ${GREEN}⚡${NC} $1 ${DIM}(auto-fixed)${NC}"; fi
  fix_count=$((fix_count + 1))
}

skipped() {
  if $QUIET_MODE; then :
  elif $REPORT_MODE; then echo "- ⊘ $1"
  else echo -e "  ${DIM}⊘ $1${NC}"; fi
  skip_count=$((skip_count + 1))
}

audit_warn() {
  local desc="$1"
  local remediation="${2:-}"

  if $QUIET_MODE; then :
  elif $REPORT_MODE; then
    if [ -n "$remediation" ]; then
      echo "- ⚠️ $desc — Fix: $remediation"
    else
      echo "- ⚠️ $desc"
    fi
  elif [ -n "$remediation" ]; then
    echo -e "  ${YELLOW}⚠${NC} $desc ${DIM}(fix: $remediation)${NC}"
  else
    echo -e "  ${YELLOW}⚠${NC} $desc"
  fi
  warn_count=$((warn_count + 1))
}

#!/bin/bash
# mac-baseline.sh — the numbers a person sees before and after the install:
# zsh start median, free disk, and the dotfiles LaunchAgent count.
# Sourced by bin/dotfiles-install (plan) and bin/dotfiles-metrics (--baseline),
# so both print the same lines. Functions only; no state.

# Median wall time of an interactive zsh start in ms over N runs (default 3,
# so plan stays fast). It times `zsh -i -c 'exit 0'`: a plain `exit` returns
# the status of the last startup line (macOS's /etc/zshrc ends with a test
# that is false outside Terminal.app), so only "zsh could not run or
# crashed" makes a run fail, and only runs that exit 0 count.
baseline_zsh_ms() {
  local runs="${1:-3}" i
  command -v zsh >/dev/null 2>&1 || return 1
  for ((i = 0; i < runs; i++)); do
    _baseline_run_ms zsh -i -c 'exit 0'
  done | sort -n | awk '{ v[NR] = $1 } END { if (NR) print v[int((NR + 1) / 2)]; else exit 1 }'
}

# _baseline_run_ms <command...>: the wall time of one run in whole ms,
# rounded up, or nothing when the command fails. A run that finished took
# more than 0 ms, so the result is at least 1: a fresh zsh can start in
# under 10 ms, which /usr/bin/time (10 ms steps) printed as 0. perl's
# Time::HiRes measures in microseconds; macOS's /usr/bin/perl comes first
# (DOTFILES_BASELINE_PERL names another; set it empty for no perl), run
# without PERL5LIB or PERL5OPT so another perl's modules cannot break it.
# perl prints the number, or "fail" when the command failed, and exits 0;
# any other exit means perl itself could not do it, and /usr/bin/time is
# used instead (its number rounded up the same way, read with a decimal
# point or comma). Always returns 0, so a `set -e` caller is never stopped
# by one failed run.
_baseline_run_ms() {
  local perl rc=0 out real
  if [ -n "${DOTFILES_BASELINE_PERL+set}" ]; then perl="$DOTFILES_BASELINE_PERL"
  elif [ -x /usr/bin/perl ]; then perl=/usr/bin/perl
  else perl="$(command -v perl 2>/dev/null || true)"
  fi
  if [ -n "$perl" ]; then
    # shellcheck disable=SC2016 # perl code, not shell
    out="$(env -u PERL5LIB -u PERL5OPT "$perl" -MTime::HiRes=time -e '
      open(my $out, ">&", \*STDOUT) or exit 3;
      open(STDOUT, ">", "/dev/null"); open(STDERR, ">", "/dev/null");
      my $t = time; my $status = system(@ARGV); my $ms = (time - $t) * 1000;
      if ($status != 0) { print $out "fail\n"; exit 0; }
      my $c = int($ms); $c++ if $ms > $c; $c = 1 if $c < 1;
      print $out "$c\n";' "$@" </dev/null 2>/dev/null)" || rc=$?
    if [ "$rc" = 0 ]; then
      case "$out" in
        fail) return 0 ;;
        *[!0-9]* | "") ;;  # not a number: use the fallback
        *) printf '%s\n' "$out"; return 0 ;;
      esac
    fi
  fi
  real="$({ /usr/bin/time -p sh -c '"$@" >/dev/null 2>&1 </dev/null' _ "$@"; } 2>&1 >/dev/null)" || return 0
  printf '%s\n' "$real" | LC_ALL=C awk '/^real/ { sub(/,/, ".", $2); ms = $2 * 1000; c = int(ms); if (ms > c) c++; if (c < 1) c = 1; print c }'
  return 0
}

# Free space on the volume that holds $HOME, in GB with one decimal.
baseline_free_gb() {
  df -k "$HOME" 2>/dev/null | awk 'NR == 2 { printf "%.1f\n", $4 / 1048576 }'
}

baseline_launchagents() {
  local n=0 plist
  for plist in "$HOME/Library/LaunchAgents"/*.plist; do [ -e "$plist" ] && n=$((n + 1)); done
  printf '%s\n' "$n"
}

# Disk a profile adds: Homebrew packages with their dependencies, the apps
# (full only), and the uv Python tools. Measured from installed sizes on one
# Mac (2026-10-18); Homebrew's download cache adds about as much again while
# it installs.
baseline_profile_disk() {
  case "$1" in
    full) printf 'about 3 GB (Homebrew packages, apps, and Python tools)' ;;
    *) printf 'about 1.5 GB (Homebrew packages and Python tools)' ;;
  esac
}

# The shared lines. $1 is the indent.
baseline_report() {
  local pad="${1:-}" ms
  if ms="$(baseline_zsh_ms "${DOTFILES_BASELINE_ZSH_RUNS:-3}")" && [ -n "$ms" ]; then
    printf '%szsh start: median %s ms of %s runs (your shell config now)\n' "$pad" "$ms" "${DOTFILES_BASELINE_ZSH_RUNS:-3}"
  else
    printf '%szsh start: not measured (zsh did not start)\n' "$pad"
  fi
  printf '%sFree disk: %s GB\n' "$pad" "$(baseline_free_gb)"
  printf '%sLaunchAgents: %s in ~/Library/LaunchAgents\n' "$pad" "$(baseline_launchagents)"
}

# Agent setup on this Mac before the install: Claude Code skills, hook
# commands, always-loaded CLAUDE.md size, and the permission mode. Plain
# shell (jq may not exist yet). CLAUDE_CONFIG_DIR moves Claude's folder.
_claude_dir() { printf '%s' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; }
baseline_claude_skills() {
  local n=0 entry
  for entry in "$(_claude_dir)/skills"/*; do [ -e "$entry" ] && n=$((n + 1)); done
  printf '%s\n' "$n"
}
baseline_claude_hooks() {
  local f n
  f="$(_claude_dir)/settings.json"
  [ -f "$f" ] || { printf '0\n'; return; }
  # Count the "command" key only; "type": "command" holds the same word.
  n="$(grep -o '"command"[[:space:]]*:' "$f" 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s\n' "${n:-0}"
}
baseline_claude_md_bytes() {
  local f n
  f="$(_claude_dir)/CLAUDE.md"
  [ -f "$f" ] || { printf '0\n'; return; }
  n="$(wc -c <"$f" | tr -d ' ')"
  printf '%s\n' "${n:-0}"
}
baseline_claude_permissions() {
  local f mode
  f="$(_claude_dir)/settings.json"
  [ -f "$f" ] || { printf 'none\n'; return; }
  mode="$(grep -o '"defaultMode"[[:space:]]*:[[:space:]]*"[A-Za-z]*"' "$f" 2>/dev/null | head -1 | sed -E 's/.*"([A-Za-z]*)"$/\1/')"
  printf '%s\n' "${mode:-default}"
}

# ── Install receipt ──────────────────────────────────────────────────────
# The before/after record of one install, so `dotfiles metrics --gains` can
# show what changed. Plain shell, no jq: the snapshot is taken at the very
# start of `run`, before preflight installs anything (jq included).
# Files (state-dir scope, kept until the user deletes them):
#   install-before.json   the first snapshot; never overwritten, so it stays
#                         pre-install even when `run` is repeated
#   install-receipt.json  profile + that snapshot + the latest run's outcome

receipt_dir() { printf '%s/dotfiles' "${XDG_STATE_HOME:-$HOME/.local/state}"; }

_receipt_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# receipt_begin <profile>: take the before snapshot once, and start the clock.
receipt_begin() {
  local dir ms
  dir="$(receipt_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0
  RECEIPT_PROFILE="$1"
  RECEIPT_STARTED_AT="$(_receipt_now)"
  RECEIPT_START_S="$(date +%s)"
  if [ ! -s "$dir/install-before.json" ]; then
    ms="$(baseline_zsh_ms "${DOTFILES_BASELINE_ZSH_RUNS:-3}" 2>/dev/null)" || ms=""
    printf '{"taken_at":"%s","zsh_ms":%s,"free_gb":%s,"launchagents":%s,"claude_skills":%s,"claude_hooks":%s,"claude_md_bytes":%s,"claude_permissions":"%s"}\n' \
      "$RECEIPT_STARTED_AT" "${ms:-null}" "$(baseline_free_gb)" "$(baseline_launchagents)" \
      "$(baseline_claude_skills)" "$(baseline_claude_hooks)" "$(baseline_claude_md_bytes)" "$(baseline_claude_permissions)" \
      >"$dir/install-before.json" 2>/dev/null || true
  fi
}

# receipt_finish <ok:true|false> [failed step]: write the receipt. Never fails
# the install: a receipt is a record, not a step.
receipt_finish() {
  [ -n "${RECEIPT_START_S:-}" ] || return 0
  local dir before failed=""
  dir="$(receipt_dir)"
  before="$(cat "$dir/install-before.json" 2>/dev/null)" || before=""
  [ -n "$before" ] || before="null"
  # Step names come from this script; keep JSON safe anyway.
  [ -z "${2:-}" ] || failed=",\"failed_step\":\"$(printf '%s' "$2" | tr -d '"\\')\""
  printf '{"profile":"%s","before":%s,"run":{"started_at":"%s","finished_at":"%s","seconds":%s,"ok":%s%s}}\n' \
    "${RECEIPT_PROFILE:-core}" "$before" "$RECEIPT_STARTED_AT" "$(_receipt_now)" \
    "$(($(date +%s) - RECEIPT_START_S))" "$1" "$failed" >"$dir/install-receipt.json" 2>/dev/null || true
  RECEIPT_START_S=""
}

# gains_report: before (from the receipt) vs now, time to configured, and the
# automation minutes since the install. Needs jq, which the install adds.
gains_report() {
  local receipt stats before_ms before_gb before_la now_ms now_gb now_la secs ok finished saved
  receipt="$(receipt_dir)/install-receipt.json"
  if [ ! -s "$receipt" ]; then
    printf 'No install receipt yet. dotfiles-install run saves one; then run this again.\n'
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { printf 'dotfiles metrics --gains needs jq (brew install jq).\n'; return 1; }
  before_ms="$(jq -r '.before.zsh_ms // "n/a"' "$receipt")"
  before_gb="$(jq -r '.before.free_gb // "n/a"' "$receipt")"
  before_la="$(jq -r '.before.launchagents // "n/a"' "$receipt")"
  secs="$(jq -r '.run.seconds // empty' "$receipt")"
  ok="$(jq -r '.run.ok // empty' "$receipt")"
  finished="$(jq -r '.run.finished_at // empty' "$receipt")"
  now_ms="$(baseline_zsh_ms "${DOTFILES_BASELINE_ZSH_RUNS:-3}" 2>/dev/null)" || now_ms="n/a"
  now_gb="$(baseline_free_gb)"
  now_la="$(baseline_launchagents)"

  printf 'Since the install (%s, profile %s)\n' "$(jq -r '.before.taken_at // "unknown"' "$receipt")" "$(jq -r '.profile' "$receipt")"
  printf '%-22s %10s %10s\n' "Metric" "Before" "Now"
  printf '%-22s %10s %10s\n' "zsh start (ms)" "$before_ms" "${now_ms:-n/a}"
  printf '%-22s %10s %10s\n' "Free disk (GB)" "$before_gb" "$now_gb"
  printf '%-22s %10s %10s\n' "LaunchAgents" "$before_la" "$now_la"
  printf '%-22s %10s %10s\n' "Claude skills" "$(jq -r '.before.claude_skills // "n/a"' "$receipt")" "$(baseline_claude_skills)"
  printf '%-22s %10s %10s\n' "Claude hooks" "$(jq -r '.before.claude_hooks // "n/a"' "$receipt")" "$(baseline_claude_hooks)"
  printf '%-22s %10s %10s\n' "CLAUDE.md (bytes)" "$(jq -r '.before.claude_md_bytes // "n/a"' "$receipt")" "$(baseline_claude_md_bytes)"
  printf '%-22s %10s %10s\n' "Claude permissions" "$(jq -r '.before.claude_permissions // "n/a"' "$receipt")" "$(baseline_claude_permissions)"
  if [ -n "$secs" ]; then
    if [ "$secs" -ge 60 ]; then printf 'Time to configured: %s min' "$(((secs + 30) / 60))"; else printf 'Time to configured: %s s' "$secs"; fi
    [ "$ok" = "true" ] && printf '\n' || printf ' (the run did not finish: %s)\n' "$(jq -r '.run.failed_step // "unknown step"' "$receipt")"
  fi
  stats="${DOTFILES_STATS_FILE:-$HOME/.dotfiles-stats.jsonl}"
  if [ -n "$finished" ] && [ -s "$stats" ]; then
    saved="$(jq -rs --arg t "$finished" '[.[] | select((.timestamp // "") >= $t) | (.seconds_saved // 0)] | add // 0 | (. / 60 | floor)' "$stats" 2>/dev/null)" || saved=""
    [ -z "$saved" ] || printf 'Automation since the install: %s min saved (estimate: each script adds a fixed time per run)\n' "$saved"
  fi
}

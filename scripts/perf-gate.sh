#!/bin/bash
# perf-gate — fail when a tracked command got slower than the merge-base.
#
# The gate times each command in config/perf-budget.tsv in two trees in the
# same run: this working tree (head) and a clean checkout of the merge-base
# with the default branch (base). It needs no stored baseline, so it gives the
# same verdict on any machine.
#
# A command fails when
#   head_min > base_min * 1.10  AND  head_min - base_min > 3 ms   (slower), or
#   head_min > its ceiling in the budget file                     (over-ceiling).
# A command whose file the base commit does not have is "new": only the ceiling
# applies. Any other problem at the base (the command fails there, the checkout
# is broken, no base commit) is a setup error, exit 2: the gate never passes a
# comparison it could not make.
#
# Usage: scripts/perf-gate.sh [--json] [--force]
#   --json   print one JSON object (per command: base_min, head_min, ratio, verdict)
#   --force  time the commands even when the diff touches no runtime path
# Exit: 0 pass or skipped, 1 a command is slower or over its ceiling, 2 setup error.
#
# Env:
#   PERF_GATE_BASE       ref to compare with (default: origin's default branch)
#   PERF_GATE_NO_BASE    1 = with no base commit, check the ceilings only
#                        (default: no base commit is a setup error)
#   PERF_GATE_RUNS       timed runs per tree (default 15)
#   PERF_GATE_WARMUPS    untimed runs per tree first (default 2)
#   PERF_GATE_HEAVY_RUN  0 = never call heavy-run (tests)
#
# Timing choices:
# - perl with Time::HiRes (scripts/perf-gate.pl), not hyperfine. bash 3.2 has no $EPOCHREALTIME, and
#   perl ships with macOS, so the gate works on a Mac without Homebrew. One
#   perl process starts every run of both trees, so base and head runs are
#   truly interleaved (B H H B ...) and see the same machine load. hyperfine
#   would need one process per tree and per round to do that.
# - The minimum of the runs, not the mean: noise only adds time, so the
#   minimum is the most stable estimate (Chen and Revels 2016).
# - A command that looks slower is timed again (up to two more rounds) and the
#   minimums are merged. A real slowdown stays; a load spike does not.
# - The base is a detached git worktree, not a `git archive` export: `dotfiles
#   --version` calls git, and an export without git data would take another
#   code path than the head tree and skew the comparison. It lives under
#   ~/.cache/dotfiles/perf-gate.noindex/<commit> (Spotlight skips .noindex).
#   The gate removes only its own checkouts there, under a lock, and never
#   runs a repo-wide `git worktree prune`.
# - Scope comes from the path lists of the base AND the head budget file, so a
#   PR cannot switch the gate off by editing its own list.
# - Every run gets an empty environment plus a scratch HOME, so no telemetry,
#   stats, or error log is written, and BASH_ENV cannot point a base run at
#   another checkout.
# - Timing runs through `heavy-run --exclusive` when heavy-run is on PATH.
#   Inside a heavy-run slot (HEAVY_RUN_SLOT is set, as in `heavy-run make
#   check`) it runs directly: a nested exclusive run would wait for its own
#   parent forever.
set -uo pipefail

json=0
force=0
for arg in "$@"; do
  case "$arg" in
    --json) json=1 ;;
    --force) force=1 ;;
    -h | --help) sed -n '2,/^# Timing choices/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "perf gate: unknown argument $arg (try --help)" >&2; exit 2 ;;
  esac
done

runs="${PERF_GATE_RUNS:-15}"
warmups="${PERF_GATE_WARMUPS:-2}"
case "$runs" in '' | *[!0-9]* | 0) echo "perf gate: PERF_GATE_RUNS must be a number above 0" >&2; exit 2 ;; esac
case "$warmups" in '' | *[!0-9]*) echo "perf gate: PERF_GATE_WARMUPS must be a number" >&2; exit 2 ;; esac

script_dir="$(cd "$(dirname "$0")" && pwd -P)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "perf gate: not in a git repository" >&2; exit 2; }
cd "$root" || exit 2
budget="$root/config/perf-budget.tsv"
[ -f "$budget" ] || { echo "perf gate: $budget is missing" >&2; exit 2; }
# The budget file must not be able to empty its own gate.
grep -q '^PERF_GATE_PATH=.' "$budget" || { echo "perf gate: $budget has no PERF_GATE_PATH line" >&2; exit 2; }
grep -qvE '^[[:space:]]*(#|$)|^PERF_GATE_(PATH|ALLOW)=' "$budget" || { echo "perf gate: $budget lists no command" >&2; exit 2; }

skip() {
  if [ "$json" = 1 ]; then printf '{"skipped":true,"reason":"%s"}\n' "$1"; else echo "perf gate: skipped ($1)"; fi
  exit 0
}

# ── Base commit: the merge-base with the default branch ──────────────
base_ref="${PERF_GATE_BASE:-}"
if [ -z "$base_ref" ]; then
  base_ref="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$base_ref" ] || base_ref="origin/feat/chezmoi"
fi
base_sha="$(git merge-base HEAD "$base_ref" 2>/dev/null || true)"
base_date=""
if [ -n "$base_sha" ]; then
  # The date shows a stale ref: fetch when it is old.
  base_date="$(git log -1 --format=%cd --date=short "$base_ref" 2>/dev/null || true)"
  echo "perf gate: base ref $base_ref (last commit $base_date), merge-base ${base_sha:0:12}" >&2
elif [ "${PERF_GATE_NO_BASE:-0}" = 1 ]; then
  echo "perf gate: no base commit for $base_ref; PERF_GATE_NO_BASE=1, so only the ceilings apply" >&2
else
  echo "perf gate: no base commit: cannot find the merge-base of HEAD and $base_ref" >&2
  echo "Fix: git fetch origin, or set PERF_GATE_BASE=<ref>. PERF_GATE_NO_BASE=1 checks the ceilings only." >&2
  exit 2
fi

# ── Scope: only a diff that touches a runtime path is timed ──────────
# The path list is the union of the base and the head budget file. With no
# base commit the diff is unknown, so the gate runs.
if [ "$force" = 0 ] && [ -n "$base_sha" ]; then
  runtime_change=0
  paths="$(
    { cat "$budget"; git show "$base_sha:config/perf-budget.tsv" 2>/dev/null; } | sed -n 's/^PERF_GATE_PATH=\(..*\)$/\1/p'
  )"
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    while IFS= read -r prefix; do
      case "$changed" in "$prefix" | "${prefix%/}"/*) runtime_change=1; break 2 ;; esac
    done <<< "$paths"
  done < <(git diff --no-renames --name-only "$base_sha" 2>/dev/null; git ls-files -o --exclude-standard 2>/dev/null)
  [ "$runtime_change" = 1 ] || skip "no runtime change"
fi

# ── Timing and verdicts (scripts/perf-gate.pl) ───────────────────────
cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/perf-gate.noindex"
perl_bin=/usr/bin/perl
[ -x "$perl_bin" ] || perl_bin=perl
set -- "$perl_bin" "$script_dir/perf-gate.pl" "$root" "$base_sha" "$cache" "$runs" "$warmups" "$json" "$base_ref" "$base_date"
if [ "${PERF_GATE_HEAVY_RUN:-1}" = 0 ]; then
  "$@"
elif [ -n "${HEAVY_RUN_SLOT:-}" ]; then
  echo "perf gate: already inside a heavy-run slot; timing runs directly" >&2
  "$@"
elif command -v heavy-run >/dev/null 2>&1; then
  echo "perf gate: waiting for an exclusive heavy-run slot (it starts when no other heavy run is active; see: heavy-run --status)" >&2
  heavy-run --exclusive "$@"
else
  echo "perf gate: heavy-run not found; timing runs directly (other work on this machine can add noise)" >&2
  "$@"
fi

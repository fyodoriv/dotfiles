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
# A command that does not exist at the base is "new": only the ceiling applies.
#
# Usage: scripts/perf-gate.sh [--json] [--force]
#   --json   print one JSON object (per command: base_min, head_min, ratio, verdict)
#   --force  time the commands even when the diff touches no runtime path
# Exit: 0 pass or skipped, 1 a command is slower or over its ceiling, 2 setup error.
#
# Env:
#   PERF_GATE_BASE       ref to compare with (default: origin's default branch)
#   PERF_GATE_RUNS       timed runs per tree (default 15)
#   PERF_GATE_WARMUPS    untimed runs per tree first (default 2)
#   PERF_GATE_HEAVY_RUN  0 = never call heavy-run (tests)
#
# Timing choices:
# - perl with Time::HiRes, not hyperfine. bash 3.2 has no $EPOCHREALTIME, and
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
#   code path than the head tree and skew the comparison.
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
    -h | --help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "perf gate: unknown argument $arg (try --help)" >&2; exit 2 ;;
  esac
done

runs="${PERF_GATE_RUNS:-15}"
warmups="${PERF_GATE_WARMUPS:-2}"
case "$runs" in '' | *[!0-9]* | 0) echo "perf gate: PERF_GATE_RUNS must be a number above 0" >&2; exit 2 ;; esac
case "$warmups" in '' | *[!0-9]*) echo "perf gate: PERF_GATE_WARMUPS must be a number" >&2; exit 2 ;; esac

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "perf gate: not in a git repository" >&2; exit 2; }
cd "$root" || exit 2
budget="$root/config/perf-budget.tsv"
[ -f "$budget" ] || { echo "perf gate: $budget is missing" >&2; exit 2; }

skip() {
  if [ "$json" = 1 ]; then printf '{"skipped":true,"reason":"%s"}\n' "$1"; else echo "perf gate: skipped ($1)"; fi
  exit 0
}

# ── Base commit: the merge-base with the default branch ──────────────
base_ref="${PERF_GATE_BASE:-}"
if [ -z "$base_ref" ]; then
  base_ref="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$base_ref" ] || base_ref="origin/feat/chezmoi"
fi
base_sha="$(git merge-base HEAD "$base_ref" 2>/dev/null || true)"

# ── Scope: only a diff that touches a runtime path is timed ──────────
# With no base commit the diff is unknown, so the gate runs (ceilings only).
if [ "$force" = 0 ] && [ -n "$base_sha" ]; then
  runtime_change=0
  while IFS= read -r changed; do
    [ -n "$changed" ] || continue
    while IFS= read -r line; do
      case "$line" in PERF_GATE_PATH=?*) ;; *) continue ;; esac
      prefix="${line#PERF_GATE_PATH=}"
      case "$changed" in "$prefix" | "${prefix%/}"/*) runtime_change=1; break 2 ;; esac
    done < "$budget"
  done < <(git diff --name-only "$base_sha" 2>/dev/null; git ls-files -o --exclude-standard 2>/dev/null)
  [ "$runtime_change" = 1 ] || skip "no runtime change"
fi

# ── Base checkout: a cached detached worktree, keyed by commit ───────
base_dir=""
if [ -n "$base_sha" ]; then
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/perf-gate"
  base_dir="$cache/$base_sha"
  if [ ! -f "$base_dir.ready" ]; then
    mkdir -p "$cache" || { echo "perf gate: cannot create $cache" >&2; exit 2; }
    rm -rf "$base_dir"
    git worktree prune 2>/dev/null
    if git -c core.hooksPath=/dev/null worktree add --detach --quiet "$base_dir" "$base_sha" >/dev/null 2>&1; then
      : > "$base_dir.ready"
    elif [ ! -f "$base_dir.ready" ]; then
      echo "perf gate: cannot check out the base commit $base_sha at $base_dir" >&2
      exit 2
    fi
  fi
  touch "$base_dir.ready"
  # Keep this checkout and the newest other one.
  kept=0
  while IFS= read -r ready; do
    [ -n "$ready" ] || continue
    old="${ready%.ready}"
    [ "$old" != "$base_dir" ] || continue
    kept=$((kept + 1))
    [ "$kept" -gt 1 ] || continue
    git worktree remove --force "$old" >/dev/null 2>&1 || rm -rf "$old"
    rm -f "$ready"
  done < <(ls -1t "$cache"/*.ready 2>/dev/null)
  git worktree prune 2>/dev/null
else
  echo "perf gate: no base commit found for ${base_ref}; only the ceilings apply" >&2
fi

# ── Timing and verdicts ──────────────────────────────────────────────
# shellcheck disable=SC2016 # perl program, not shell
timer='
use strict; use warnings;
use Time::HiRes qw(time);
use File::Temp qw(tempdir);
use POSIX ();
my ($head, $base, $budget, $runs, $warmups, $json, $sha) = @ARGV;
my ($RATIO, $FLOOR_MS) = (1.10, 3);
$SIG{__DIE__} = sub { print STDERR $_[0]; exit 2 };   # setup errors exit 2

sub parse {
  my ($file) = @_;
  my (@cmds, %allow);
  open(my $fh, "<", $file) or return (\@cmds, \%allow);
  while (my $l = <$fh>) {
    chomp $l;
    next if $l =~ /^\s*(#|$)/ || $l =~ /^PERF_GATE_PATH=/;
    if ($l =~ /^PERF_GATE_ALLOW=([A-Za-z0-9_.-]+):\s*(\S.*)$/) { $allow{$1} = $2; next; }
    my ($name, $ceiling, $argv, $stdin) = split /\t/, $l;
    die "perf gate: bad line $. in $file (want: name<TAB>ceiling_ms<TAB>command[<TAB>stdin])\n"
      unless defined $argv && $name =~ /^[A-Za-z0-9_.-]+$/ && $ceiling =~ /^\d+$/ && $argv =~ /\S/;
    push @cmds, { name => $name, ceiling => $ceiling, argv => [split " ", $argv], stdin => $stdin // "" };
  }
  close $fh;
  return (\@cmds, \%allow);
}

my ($cmds, $allow) = parse($budget);
die "perf gate: $budget lists no command\n" unless @$cmds;
my (undef, $base_allow) = $base ne "" ? parse("$base/config/perf-budget.tsv") : ([], {});

my $scratch = tempdir("perf-gate.XXXXXX", TMPDIR => 1, CLEANUP => 1);
mkdir "$scratch/home";
%ENV = (
  PATH => $ENV{PATH} // "/usr/bin:/bin", HOME => "$scratch/home", TMPDIR => $ENV{TMPDIR} // "/tmp",
  HEAVY_RUN_DIR => "$scratch/heavy-run", DO_NOT_TRACK => 1, DOTFILES_STATS_LOG => 0, DOTFILES_ERRORS_LOG => 0,
);

# Run the command once in $dir. Returns (milliseconds, exit status).
sub run_once {
  my ($dir, $c) = @_;
  my $t0 = time;
  my $pid = fork;
  die "perf gate: fork failed: $!\n" unless defined $pid;
  if (!$pid) {
    chdir $dir or POSIX::_exit(127);
    open(STDIN, "<", $c->{stdin_file}) or POSIX::_exit(127);
    open(STDOUT, ">", "/dev/null"); open(STDERR, ">", "/dev/null");
    exec { $c->{argv}[0] } @{ $c->{argv} } or POSIX::_exit(127);
  }
  waitpid($pid, 0);
  return ((time - $t0) * 1000, $?);
}

sub slower { my ($b, $h) = @_; return $h > $b * $RATIO && $h - $b > $FLOOR_MS; }

my $started = time;
my (@rows, @problems);
my $n = 0;
for my $c (@$cmds) {
  $c->{stdin_file} = "/dev/null";
  if ($c->{stdin} ne "") {
    $c->{stdin_file} = "$scratch/stdin." . $n++;
    open(my $fh, ">", $c->{stdin_file}) or die "perf gate: $!\n";
    print $fh $c->{stdin}, "\n"; close $fh;
  }
  my $prog = $c->{argv}[0];
  my $has_base = $base ne "" && ($prog !~ m{/} || -x "$base/$prog");
  my ($bmin, $hmin, $failed, $count);
  my $round = sub {
    my ($times, $timed) = @_;
    for my $i (1 .. $times) {
      # Swap the order each pass, so neither tree always runs first.
      for my $side ($i % 2 ? ("base", "head") : ("head", "base")) {
        next if $side eq "base" && !$has_base;
        my ($ms, $st) = run_once($side eq "base" ? $base : $head, $c);
        if ($st != 0) {
          if ($side eq "head") { $failed = $st; return; }
          $has_base = 0; $bmin = undef; next;
        }
        next unless $timed;
        if ($side eq "base") { $bmin = $ms if !defined $bmin || $ms < $bmin; }
        else { $hmin = $ms if !defined $hmin || $ms < $hmin; $count++; }
      }
    }
  };
  $round->($warmups, 0);
  $round->($runs, 1) unless $failed;
  for (1 .. 2) {
    last if $failed || !$has_base || !slower($bmin, $hmin);
    $round->($runs, 1);
  }
  my %r = (name => $c->{name}, ceiling => $c->{ceiling}, base => $has_base ? $bmin : undef, head => $hmin, runs => $count // 0);
  if ($failed) {
    $r{verdict} = "error";
    push @problems, "$c->{name}: the command failed in this tree (status " . ($failed >> 8) . "): @{ $c->{argv} }";
  } else {
    $r{ratio} = $hmin / $bmin if $has_base && $bmin > 0;
    $r{verdict} = $has_base ? "ok" : "new";
    if ($has_base && slower($bmin, $hmin)) {
      my $msg = sprintf("%s got slower: %.1f ms -> %.1f ms (%+.1f%%; the limit is +%d%% and %d ms)",
        $c->{name}, $bmin, $hmin, ($r{ratio} - 1) * 100, ($RATIO - 1) * 100 + 0.5, $FLOOR_MS);
      if (exists $allow->{ $c->{name} } && !exists $base_allow->{ $c->{name} }) { $r{verdict} = "allowed"; }
      else { $r{verdict} = "slower"; push @problems, $msg; }
    }
    if ($hmin > $c->{ceiling}) {
      $r{verdict} = "over-ceiling";
      push @problems, sprintf("%s is over its ceiling: %.1f ms > %d ms", $c->{name}, $hmin, $c->{ceiling});
    }
  }
  push @rows, \%r;
}
# An allow line is for one PR. One that the base already has is stale.
for my $name (sort keys %$allow) {
  push @problems, "PERF_GATE_ALLOW=$name is already in the base budget file: remove the line (it covers one PR only)"
    if exists $base_allow->{$name};
}

my $ok = @problems ? 0 : 1;
if ($json) {
  my $num = sub { defined $_[0] ? sprintf("%.3f", $_[0]) : "null" };
  my @items = map {
    sprintf(q({"name":"%s","base_min":%s,"head_min":%s,"ratio":%s,"ceiling_ms":%d,"runs":%d,"verdict":"%s"}),
      $_->{name}, $num->($_->{base}), $num->($_->{head}), $num->($_->{ratio}), $_->{ceiling}, $_->{runs}, $_->{verdict})
  } @rows;
  printf qq({"skipped":false,"ok":%s,"base":%s,"limit_ratio":%.2f,"limit_ms":%d,"commands":[%s]}\n),
    $ok ? "true" : "false", $sha ne "" ? qq("$sha") : "null", $RATIO, $FLOOR_MS, join(",", @items);
} else {
  for my $r (@rows) {
    printf "  %-24s base %s  head %s  %s  %s\n", $r->{name},
      defined $r->{base} ? sprintf("%7.1f ms", $r->{base}) : "         -",
      defined $r->{head} ? sprintf("%7.1f ms", $r->{head}) : "         -",
      defined $r->{ratio} ? sprintf("%+6.1f%%", ($r->{ratio} - 1) * 100) : "      -", $r->{verdict};
  }
  printf "perf gate: %s (%d commands, base %s, %.1f s)\n", $ok ? "pass" : "FAIL", scalar @rows,
    $sha ne "" ? substr($sha, 0, 12) : "none", time - $started;
}
if (!$ok) {
  print STDERR "perf gate: $_\n" for @problems;
  print STDERR "Fix, one of:\n",
    "  1. Make the command faster.\n",
    "  2. If the new cost is intended and worth it: raise its ceiling in config/perf-budget.tsv and say why in the PR.\n",
    "     For a step over 10% in one PR, also add a line PERF_GATE_ALLOW=<name>:<reason> to that file;\n",
    "     the next PR removes the line.\n";
}
exit($ok ? 0 : 1);
'

perl_bin=/usr/bin/perl
[ -x "$perl_bin" ] || perl_bin=perl
set -- "$perl_bin" -e "$timer" -- "$root" "$base_dir" "$budget" "$runs" "$warmups" "$json" "$base_sha"
if [ "${PERF_GATE_HEAVY_RUN:-1}" = 0 ]; then
  "$@"
elif [ -n "${HEAVY_RUN_SLOT:-}" ]; then
  echo "perf gate: already inside a heavy-run slot; timing runs directly" >&2
  "$@"
elif command -v heavy-run >/dev/null 2>&1; then
  heavy-run --exclusive "$@"
else
  echo "perf gate: heavy-run not found; timing runs directly (other work on this machine can add noise)" >&2
  "$@"
fi

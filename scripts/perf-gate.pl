#!/usr/bin/perl
# perf-gate.pl — the timer behind scripts/perf-gate.sh. Do not call it by hand.
#
# Usage: perf-gate.pl <head-dir> <base-sha|""> <cache-dir> <runs> <warmups> <json 0|1> <base-ref> <base-ref-date>
#
# 1. Builds (or reuses) the base checkout: a detached git worktree at
#    <cache-dir>/<base-sha>. A checkout is valid only when its HEAD is that
#    commit and `git status` shows no changed, new, or ignored file; any other
#    checkout is built again. The gate writes <cache-dir>/<base-sha>.ready for
#    each checkout it builds. It removes a folder only with that marker, and
#    it unlinks a symlink without following it. One exception, for a checkout
#    from before the marker existed: the prune removes an unmarked folder
#    that git lists as a worktree of this repo and that is over 7 days old.
#    Build and prune happen under <cache-dir>/lock, and every gate
#    holds a shared lock on <cache-dir>/<sha>.use while it times, so no gate
#    removes a checkout that another gate uses.
# 2. Times each command of config/perf-budget.tsv in both trees, in turn. A
#    name that the base budget file has runs the BASE row's command at the
#    base, so a PR cannot dodge the comparison by editing the row.
#    "Slower" needs two rules to agree: the fastest head run is over the limit
#    against the fastest base run, AND the median of the paired differences
#    (head minus base, pass by pass) is over the limit too. Load noise moves
#    one of them; a real slowdown moves both.
# 3. Prints the verdicts. Exit: 0 pass, 1 slower or over a ceiling, 2 setup
#    error (a command that fails in either tree is a setup error). A command
#    over its ceiling at the base too is "over-ceiling-at-base": not a failure.
#
# A PR that changes scripts/perf-gate.sh, scripts/perf-gate.pl, or
# tests/perf-gate.bats changes its own judge. The gate says so and needs
# PERF_GATE_ALLOW=perf-gate:<reason>.
#
# An allow line counts when the base budget file does not have the same line
# (same name and same reason). A line that the base has unchanged is stale.
#
# The reasons for each timing choice are in scripts/perf-gate.sh.
use strict; use warnings;
use Time::HiRes qw(time);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Glob qw(bsd_glob);
use Cwd qw(realpath);
use Fcntl qw(:flock);
use POSIX ();

my ($head, $sha, $cache, $runs, $warmups, $json, $ref, $ref_date) = @ARGV;
die "usage: perf-gate.pl <head-dir> <base-sha> <cache-dir> <runs> <warmups> <json> <ref> <ref-date>\n" unless defined $ref_date;
my ($RATIO, $FLOOR_MS) = (1.10, 3);
# The gate's own files, and the allow name for a PR that changes them.
# The Makefile is not here: most Makefile changes are not about this gate, and
# tests/perf-gate.bats (which is here) pins the Makefile recipe.
my @GATE_FILES = ("scripts/perf-gate.sh", "scripts/perf-gate.pl", "tests/perf-gate.bats");
my $SELF_ALLOW = "perf-gate";
# A setup error exits 2. $^S is true inside eval: leave those to the caller.
$SIG{__DIE__} = sub { die @_ if $^S; print STDERR $_[0]; exit 2 };

sub git_out {
  my ($dir, @args) = @_;
  open(my $fh, "-|", "git", "-C", $dir, @args) or return "";
  my $out = do { local $/; <$fh> } // "";
  close $fh;
  chomp $out;
  return $out;
}
sub git_quiet {
  my ($dir, @args) = @_;
  my $pid = fork;
  die "perf gate: fork failed: $!\n" unless defined $pid;
  if (!$pid) {
    open(STDOUT, ">", "/dev/null"); open(STDERR, ">", "/dev/null");
    exec("git", "-C", $dir, @args) or POSIX::_exit(127);
  }
  waitpid($pid, 0);
  return $? == 0;
}

sub parse {
  my ($file) = @_;
  my (@cmds, %allow, %seen);
  open(my $fh, "<", $file) or return (\@cmds, \%allow);
  while (my $l = <$fh>) {
    chomp $l;
    next if $l =~ /^\s*(#|$)/ || $l =~ /^PERF_GATE_PATH=/;
    if ($l =~ /^PERF_GATE_ALLOW=([A-Za-z0-9_.-]+):\s*\S/) { $allow{$1} = $l; next; }   # name => the whole line
    my ($name, $ceiling, $argv, $stdin) = split /\t/, $l;
    die "perf gate: bad line $. in $file (want: name<TAB>ceiling_ms<TAB>command[<TAB>stdin])\n"
      unless defined $argv && $name =~ /^[A-Za-z0-9_.-]+$/ && $ceiling =~ /^\d+$/ && $argv =~ /\S/;
    die "perf gate: command $name is listed twice in $file\n" if $seen{$name}++;
    die "perf gate: the name $SELF_ALLOW is reserved for a change to the gate itself ($file line $.)\n" if $name eq $SELF_ALLOW;
    push @cmds, { name => $name, ceiling => $ceiling, argv => [split " ", $argv], stdin => $stdin // "" };
  }
  close $fh;
  return (\@cmds, \%allow);
}

# ── Base checkout ────────────────────────────────────────────────────
# Remove one checkout of this gate. Only a path <cache>/<40 hex> is ever
# touched. A symlink is unlinked, never followed. A folder is removed only
# when the gate's marker <path>.ready says the gate built it. With $old_too
# (the prune), a folder with no marker is removed too when old_checkout says
# it is an old checkout of the gate. Returns 1 when the path is gone, 0 when
# a folder without the marker was left alone.
my $OLD_DAYS = 7;
# True for a checkout from before the marker existed: git lists the path as a
# worktree of this repo, and the folder is over $OLD_DAYS days old.
sub old_checkout {
  my ($dir) = @_;
  my $mtime = (lstat $dir)[9];
  return 0 unless defined $mtime && time - $mtime > $OLD_DAYS * 86400;
  my $real = realpath($dir) // $dir;
  for my $line (split /\n/, git_out($head, "worktree", "list", "--porcelain")) {
    next unless $line =~ /^worktree (.+)$/;
    return 1 if $1 eq $dir || $1 eq $real || (realpath($1) // "") eq $real;
  }
  return 0;
}
sub remove_checkout {
  my ($dir, $old_too) = @_;
  return 1 unless $cache ne "" && $dir =~ m{^\Q$cache\E/[0-9a-f]{40}$};
  if (-l $dir) { unlink $dir; unlink "$dir.ready"; return !-l $dir; }
  return 0 if -e $dir && !-e "$dir.ready" && !($old_too && old_checkout($dir));
  git_quiet($head, "worktree", "remove", "--force", $dir) if -e $dir;
  remove_tree($dir) if -e $dir;
  unlink "$dir.ready";
  return 1;
}

# True when the tree has no changed, new, or ignored file. A git error is "not clean".
sub clean_tree {
  my ($dir) = @_;
  open(my $fh, "-|", "git", "-C", $dir, "status", "--porcelain", "--ignored", "--untracked-files=all") or return 0;
  my $out = do { local $/; <$fh> } // "";
  return close($fh) && $out eq "";
}
my $base = "";
my $use_lock;   # held until exit
sub base_ok { return !-l $base && -d $base && git_out($base, "rev-parse", "HEAD") eq $sha && clean_tree($base); }
if ($sha ne "") {
  die "perf gate: bad base commit $sha\n" unless $sha =~ /^[0-9a-f]{40}$/;
  die "perf gate: the cache folder must be an absolute path, not '$cache'\n" unless $cache =~ m{^/};
  eval { make_path($cache); 1 } && -d $cache && -w $cache
    or die "perf gate: cannot create or write the cache folder $cache\n";
  open(my $lock, ">>", "$cache/lock") or die "perf gate: cannot open $cache/lock: $!\n";
  flock($lock, LOCK_EX) or die "perf gate: cannot lock $cache/lock: $!\n";
  open($use_lock, ">>", "$cache/$sha.use") or die "perf gate: cannot open $cache/$sha.use: $!\n";
  flock($use_lock, LOCK_SH) or die "perf gate: cannot lock $cache/$sha.use: $!\n";
  $base = "$cache/$sha";
  # A checkout at another commit, or one with an edited or added file, is not
  # the base: build it again.
  if (!base_ok()) {
    print STDERR "perf gate: the cached base checkout is not a clean copy of the base commit; building it again\n" if -d $base;
    remove_checkout($base)
      or die "perf gate: $base is not a clean base checkout, and the gate did not build it (no $base.ready).\n"
      . "The gate does not remove a folder it did not build. Look at it, then move or remove it by hand.\n";
    # -f: a checkout whose folder was deleted is still registered in git.
    git_quiet($head, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-f", "--detach", $base, $sha);
    die "perf gate: cannot check out a clean copy of the base commit $sha at $base\n" unless base_ok();
  }
  # The marker: the gate built this checkout, or found it valid just now.
  { open(my $m, ">>", "$base.ready") or die "perf gate: cannot write $base.ready: $!\n"; close $m; }
  utime(undef, undef, $base);
  # Keep this checkout and the newest other one. Skip any that a gate uses.
  my @others = sort { ((lstat $b)[9] // 0) <=> ((lstat $a)[9] // 0) }
    grep { $_ ne $base && m{/[0-9a-f]{40}$} && (-l $_ || -d $_) } bsd_glob("$cache/[0-9a-f]*");
  shift @others;
  for my $old (@others) {
    next unless $old =~ m{/([0-9a-f]{40})$};
    open(my $u, ">>", "$cache/$1.use") or next;
    if (flock($u, LOCK_EX | LOCK_NB)) {
      if (remove_checkout($old, 1)) { unlink "$cache/$1.use"; }
      else { print STDERR "perf gate: left $old alone: the gate did not build it (no $old.ready). Remove it by hand if it is old. (The gate prunes it itself only when git lists it as a worktree of this repo and it is over $OLD_DAYS days old.)\n"; }
    }
    close $u;
  }
  close $lock;
}

# ── Budget ───────────────────────────────────────────────────────────
my $budget = "$head/config/perf-budget.tsv";
my ($cmds, $allow) = parse($budget);
die "perf gate: $budget lists no command\n" unless @$cmds;
my ($base_cmds, $base_allow) = $base ne "" ? parse("$base/config/perf-budget.tsv") : ([], {});
my %known = map { $_->{name} => 1 } @$cmds, @$base_cmds;
$known{$SELF_ALLOW} = 1;
my %base_row = map { $_->{name} => $_ } @$base_cmds;
# An allow line counts for this PR when the base does not have the same line.
# A line that the base has with the same name and reason is stale.
sub fresh { my ($name) = @_; return exists $allow->{$name} && ($base_allow->{$name} // "") ne $allow->{$name}; }
sub reason { my ($name) = @_; (my $r = $allow->{$name}) =~ s/^[^:]*:\s*//; return $r; }

# ── A change to the gate itself ──────────────────────────────────────
# These files judge the PR that changes them. So the change must show in the
# budget file, where a reviewer looks: without a new allow line, exit 2.
if ($base ne "") {
  my @changed = grep {
    git_quiet($head, "cat-file", "-e", "$sha:$_") && !git_quiet($head, "diff", "--no-renames", "--quiet", $sha, "--", $_)
  } @GATE_FILES;
  if (@changed) {
    print STDERR "perf gate: WARNING: this change edits the gate itself (@changed). The gate judges its own PR: review these files by hand.\n";
    die "perf gate: @changed differ from the base, and no new allow line covers that.\n"
      . "Add PERF_GATE_ALLOW=$SELF_ALLOW:<reason> to config/perf-budget.tsv so the review sees it.\n"
      . (exists $allow->{$SELF_ALLOW} ? "The line there now is the same as in the base: write this PR's own reason.\n" : "")
      unless fresh($SELF_ALLOW);
    print STDERR "perf gate: allowed by PERF_GATE_ALLOW=$SELF_ALLOW: " . reason($SELF_ALLOW) . "\n";
  }
}
for my $name (sort keys %$allow) {
  die "perf gate: PERF_GATE_ALLOW=$name names no command of the budget file\n" unless $known{$name};
}
# A stale allow line stops the gate here, before any timing.
# A JSON string, with no JSON module: the gate uses core perl only.
sub json_str {
  my ($s) = @_;
  $s =~ s/(["\\])/\\$1/g;
  $s =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord $1)/ge;
  return qq("$s");
}
my @stale = map { $allow->{$_} } grep { !fresh($_) } sort keys %$allow;
if (@stale) {
  # With --json the caller still gets JSON on stdout.
  printf qq({"skipped":false,"ok":false,"problems":[%s]}\n),
    join(",", map { json_str("stale allow line: remove this line from config/perf-budget.tsv: $_") } @stale) if $json;
  print STDERR "perf gate: an allow line covers one PR, and the base budget file already has this one.\n";
  print STDERR "remove this line from config/perf-budget.tsv: $_\n" for @stale;
  print STDERR "(If this PR needs the allow again, write the line with this PR's own reason.)\n";
  exit 1;
}

my $scratch = tempdir("perf-gate.XXXXXX", TMPDIR => 1, CLEANUP => 1);
mkdir "$scratch/home";
%ENV = (
  PATH => $ENV{PATH} // "/usr/bin:/bin", HOME => "$scratch/home", TMPDIR => $ENV{TMPDIR} // "/tmp",
  HEAVY_RUN_DIR => "$scratch/heavy-run", DO_NOT_TRACK => 1, DOTFILES_STATS_LOG => 0, DOTFILES_ERRORS_LOG => 0,
);

# Run the command once in $dir. Returns (milliseconds, wait status).
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
sub median {
  my @v = sort { $a <=> $b } @_;
  return undef unless @v;
  return @v % 2 ? $v[$#v / 2] : ($v[@v / 2 - 1] + $v[@v / 2]) / 2;
}
# The second rule: the median of (head - base) over the paired passes is over
# the limit too. With no pair, the minimum rule decides alone.
sub paired_slower {
  my ($b, $delta) = @_;
  my $limit = $b * ($RATIO - 1);
  return !defined $delta || $delta > ($limit > $FLOOR_MS ? $limit : $FLOOR_MS);
}

my $started = time;
my (@rows, @problems);
my $n = 0;
for my $c (@$cmds, @$base_cmds) {
  $c->{stdin_file} = "/dev/null";
  next if $c->{stdin} eq "";
  $c->{stdin_file} = "$scratch/stdin." . $n++;
  open(my $fh, ">", $c->{stdin_file}) or die "perf gate: $!\n";
  print $fh $c->{stdin}, "\n"; close $fh;
}
for my $c (@$cmds) {
  # A name that the base budget has is never "new": the base runs its own row,
  # whatever this tree's row says now (a renamed file, a wrapper in front).
  my $bc = $base_row{ $c->{name} };
  my $has_base = defined $bc;
  if ($has_base) {
    print STDERR "perf gate: $c->{name}: the command row changed; the base runs its own row (@{ $bc->{argv} })\n"
      if "@{ $bc->{argv} }\t$bc->{stdin}" ne "@{ $c->{argv} }\t$c->{stdin}";
  } else {
    # A new name is "new" only when the base commit does not have the file. A
    # command the base has must run there.
    $bc = $c;
    (my $prog = $c->{argv}[0]) =~ s{^\./}{};
    $has_base = $base ne "" && ($prog !~ m{/} && !-e "$head/$prog" || git_quiet($head, "cat-file", "-e", "$sha:$prog"));
  }
  my ($bmin, $hmin, $count, @deltas);
  my $round = sub {
    my ($times, $timed) = @_;
    for my $i (1 .. $times) {
      my %pass;
      # Swap the order each pass, so neither tree always runs first.
      for my $side ($i % 2 ? ("base", "head") : ("head", "base")) {
        next if $side eq "base" && !$has_base;
        my ($ms, $st) = $side eq "base" ? run_once($base, $bc) : run_once($head, $c);
        # A command that fails is a setup error in either tree, never a pass or a verdict.
        my $how = $st & 127 ? "signal " . ($st & 127) : "status " . ($st >> 8);
        die "perf gate: $c->{name} failed in this tree ($how): @{ $c->{argv} }\n"
          . "The gate cannot time a command that fails. Fix the command or its row.\n" if $st != 0 && $side eq "head";
        die "perf gate: $c->{name} failed in the base checkout ($how): @{ $bc->{argv} }\n"
          . "The base has this command, so the gate cannot compare. Check $base, or fix the command row.\n" if $st != 0;
        next unless $timed;
        if ($side eq "base") { $bmin = $ms if !defined $bmin || $ms < $bmin; }
        else { $hmin = $ms if !defined $hmin || $ms < $hmin; $count++; }
        $pass{$side} = $ms;
      }
      push @deltas, $pass{head} - $pass{base} if $timed && defined $pass{base} && defined $pass{head};
    }
  };
  my $both = sub { $has_base && slower($bmin, $hmin) && paired_slower($bmin, median(@deltas)) };
  $round->($warmups || 1, 0);   # at least one untimed run: it also proves the command works
  $round->($runs, 1);
  for (1 .. 2) {
    last if !$both->();
    $round->($runs, 1);
  }
  my $delta = median(@deltas);
  my %r = (name => $c->{name}, ceiling => $c->{ceiling}, base => $bmin, head => $hmin, runs => $count // 0,
    delta => $delta, at_base => 0);
  {
    $r{ratio} = $hmin / $bmin if $has_base && $bmin > 0;
    $r{verdict} = $has_base ? "ok" : "new";
    if ($both->()) {
      my $msg = sprintf("%s got slower: %.1f ms -> %.1f ms (%+.1f%%; the limit is +%d%% and %d ms%s)",
        $c->{name}, $bmin, $hmin, ($r{ratio} - 1) * 100, ($RATIO - 1) * 100 + 0.5, $FLOOR_MS,
        defined $delta ? sprintf("; paired runs: %+.1f ms", $delta) : "");
      if (fresh($c->{name})) { $r{verdict} = "allowed"; }
      else { $r{verdict} = "slower"; push @problems, $msg; }
    } elsif ($has_base && slower($bmin, $hmin)) {
      printf STDERR "perf gate: %s: the fastest runs differ by %+.1f%%, but the paired runs do not (median difference %+.1f ms): load noise, not a slowdown\n",
        $c->{name}, ($r{ratio} - 1) * 100, $delta;
    }
    if ($hmin > $c->{ceiling}) {
      if ($has_base && $bmin > $c->{ceiling}) {
        # The base is over the ceiling too, so this tree did not cause it.
        printf STDERR "perf gate: %s is over its ceiling: %.1f ms > %d ms, but so is the base (%.1f ms): this machine is slow now, or the ceiling is too low. Not counted against this tree.\n",
          $c->{name}, $hmin, $c->{ceiling}, $bmin;
        $r{at_base} = 1;
        $r{verdict} = "over-ceiling-at-base" if $r{verdict} eq "ok";
      } else {
        $r{verdict} = "over-ceiling";
        push @problems, sprintf("%s is over its ceiling: %.1f ms > %d ms", $c->{name}, $hmin, $c->{ceiling});
      }
    }
  }
  push @rows, \%r;
}
# A tracked command may not leave the budget file silently.
my %in_head = map { $_->{name} => 1 } @$cmds;
for my $b (@$base_cmds) {
  next if $in_head{ $b->{name} } || fresh($b->{name});
  push @problems, "$b->{name} is in the base budget file but not in this one: put the row back, or add PERF_GATE_ALLOW=$b->{name}:<reason>";
}

my $ok = @problems ? 0 : 1;
my $at_base = grep { $_->{at_base} } @rows;
if ($json) {
  my $num = sub { defined $_[0] ? sprintf("%.3f", $_[0]) : "null" };
  my $str = sub { (my $s = $_[0]) =~ s/[^A-Za-z0-9_.\/:-]//g; $s ne "" ? qq("$s") : "null" };
  my @items = map {
    sprintf(q({"name":"%s","base_min":%s,"head_min":%s,"ratio":%s,"paired_delta_ms":%s,"ceiling_ms":%d,"runs":%d,"verdict":"%s","over_ceiling_at_base":%s}),
      $_->{name}, $num->($_->{base}), $num->($_->{head}), $num->($_->{ratio}), $num->($_->{delta}), $_->{ceiling},
      $_->{runs}, $_->{verdict}, $_->{at_base} ? "true" : "false")
  } @rows;
  printf qq({"skipped":false,"ok":%s,"base":%s,"base_ref":%s,"base_ref_date":%s,"limit_ratio":%.2f,"limit_ms":%d,"estimator":"min-and-paired-median","over_ceiling_at_base":%d,"problems":[%s],"commands":[%s]}\n),
    $ok ? "true" : "false", $str->($sha), $str->($ref), $str->($ref_date), $RATIO, $FLOOR_MS, $at_base,
    join(",", map { json_str($_) } @problems), join(",", @items);
} else {
  for my $r (@rows) {
    printf "  %-24s base %s  head %s  %s  %s\n", $r->{name},
      defined $r->{base} ? sprintf("%7.1f ms", $r->{base}) : "         -",
      defined $r->{head} ? sprintf("%7.1f ms", $r->{head}) : "         -",
      defined $r->{ratio} ? sprintf("%+6.1f%%", ($r->{ratio} - 1) * 100) : "      -", $r->{verdict};
  }
  printf "perf gate: %s (%d commands, base %s, %.1f s%s)\n", $ok ? "pass" : "FAIL", scalar @rows,
    $sha ne "" ? substr($sha, 0, 12) : "none", time - $started,
    $at_base ? "; $at_base over its ceiling at the base too" : "";
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

#!/usr/bin/perl
# perf-gate.pl — the timer behind scripts/perf-gate.sh. Do not call it by hand.
#
# Usage: perf-gate.pl <head-dir> <base-sha|""> <cache-dir> <runs> <warmups> <json 0|1> <base-ref> <base-ref-date>
#
# 1. Builds (or reuses) the base checkout: a detached git worktree at
#    <cache-dir>/<base-sha>. A checkout is valid only when its HEAD is that
#    commit. Build and prune happen under <cache-dir>/lock, and every gate
#    holds a shared lock on <cache-dir>/<sha>.use while it times, so no gate
#    removes a checkout that another gate uses.
# 2. Times each command of config/perf-budget.tsv in both trees, in turn.
# 3. Prints the verdicts. Exit: 0 pass, 1 slower or over a ceiling, 2 setup error.
#
# The reasons for each timing choice are in scripts/perf-gate.sh.
use strict; use warnings;
use Time::HiRes qw(time);
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use Fcntl qw(:flock);
use POSIX ();

my ($head, $sha, $cache, $runs, $warmups, $json, $ref, $ref_date) = @ARGV;
die "usage: perf-gate.pl <head-dir> <base-sha> <cache-dir> <runs> <warmups> <json> <ref> <ref-date>\n" unless defined $ref_date;
my ($RATIO, $FLOOR_MS) = (1.10, 3);
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
    if ($l =~ /^PERF_GATE_ALLOW=([A-Za-z0-9_.-]+):\s*(\S.*)$/) { $allow{$1} = $2; next; }
    my ($name, $ceiling, $argv, $stdin) = split /\t/, $l;
    die "perf gate: bad line $. in $file (want: name<TAB>ceiling_ms<TAB>command[<TAB>stdin])\n"
      unless defined $argv && $name =~ /^[A-Za-z0-9_.-]+$/ && $ceiling =~ /^\d+$/ && $argv =~ /\S/;
    die "perf gate: command $name is listed twice in $file\n" if $seen{$name}++;
    push @cmds, { name => $name, ceiling => $ceiling, argv => [split " ", $argv], stdin => $stdin // "" };
  }
  close $fh;
  return (\@cmds, \%allow);
}

# ── Base checkout ────────────────────────────────────────────────────
# Remove one checkout of this gate. Only a path <cache>/<40 hex> is ever removed.
sub remove_checkout {
  my ($dir) = @_;
  return unless $cache ne "" && $dir =~ m{^\Q$cache\E/[0-9a-f]{40}$};
  git_quiet($head, "worktree", "remove", "--force", $dir);
  remove_tree($dir) if -e $dir;
}

my $base = "";
my $use_lock;   # held until exit
if ($sha ne "") {
  die "perf gate: bad base commit $sha\n" unless $sha =~ /^[0-9a-f]{40}$/;
  make_path($cache);
  open(my $lock, ">>", "$cache/lock") or die "perf gate: cannot open $cache/lock: $!\n";
  flock($lock, LOCK_EX) or die "perf gate: cannot lock $cache/lock: $!\n";
  open($use_lock, ">>", "$cache/$sha.use") or die "perf gate: cannot open $cache/$sha.use: $!\n";
  flock($use_lock, LOCK_SH) or die "perf gate: cannot lock $cache/$sha.use: $!\n";
  $base = "$cache/$sha";
  if (!(-d $base && git_out($base, "rev-parse", "HEAD") eq $sha)) {
    remove_checkout($base);
    # -f: a checkout whose folder was deleted is still registered in git.
    git_quiet($head, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-f", "--detach", $base, $sha);
    die "perf gate: cannot check out the base commit $sha at $base\n"
      unless -d $base && git_out($base, "rev-parse", "HEAD") eq $sha;
  }
  utime(undef, undef, $base);
  # Keep this checkout and the newest other one. Skip any that a gate uses.
  my @others = sort { (stat $b)[9] <=> (stat $a)[9] } grep { $_ ne $base && -d $_ } glob("$cache/[0-9a-f]*");
  shift @others;
  for my $old (@others) {
    next unless $old =~ m{/([0-9a-f]{40})$};
    open(my $u, ">>", "$cache/$1.use") or next;
    if (flock($u, LOCK_EX | LOCK_NB)) { remove_checkout($old); unlink "$cache/$1.use"; }
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
for my $name (sort keys %$allow) {
  die "perf gate: PERF_GATE_ALLOW=$name names no command of the budget file\n" unless $known{$name};
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
  (my $prog = $c->{argv}[0]) =~ s{^\./}{};
  # "New" means one thing only: the base commit does not have the file. A
  # command the base has must run there; a failure is a setup error, never a pass.
  my $has_base = $base ne "" && ($prog !~ m{/} && !-e "$head/$prog" || git_quiet($head, "cat-file", "-e", "$sha:$prog"));
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
          die "perf gate: $c->{name} failed in the base checkout (status " . ($st >> 8) . "): @{ $c->{argv} }\n"
            . "The base has this command, so the gate cannot compare. Check $base, or fix the command row.\n";
        }
        next unless $timed;
        if ($side eq "base") { $bmin = $ms if !defined $bmin || $ms < $bmin; }
        else { $hmin = $ms if !defined $hmin || $ms < $hmin; $count++; }
      }
    }
  };
  $round->($warmups || 1, 0);   # at least one untimed run: it also proves the command works
  $round->($runs, 1) unless $failed;
  for (1 .. 2) {
    last if $failed || !$has_base || !slower($bmin, $hmin);
    $round->($runs, 1);
  }
  my %r = (name => $c->{name}, ceiling => $c->{ceiling}, base => $bmin, head => $hmin, runs => $count // 0);
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
# A tracked command may not leave the budget file silently.
my %in_head = map { $_->{name} => 1 } @$cmds;
for my $b (@$base_cmds) {
  next if $in_head{ $b->{name} } || (exists $allow->{ $b->{name} } && !exists $base_allow->{ $b->{name} });
  push @problems, "$b->{name} is in the base budget file but not in this one: put the row back, or add PERF_GATE_ALLOW=$b->{name}:<reason>";
}
# An allow line is for one PR. One that the base already has is stale.
for my $name (sort keys %$allow) {
  push @problems, "PERF_GATE_ALLOW=$name is already in the base budget file: remove the line (it covers one PR only)"
    if exists $base_allow->{$name};
}

my $ok = @problems ? 0 : 1;
if ($json) {
  my $num = sub { defined $_[0] ? sprintf("%.3f", $_[0]) : "null" };
  my $str = sub { (my $s = $_[0]) =~ s/[^A-Za-z0-9_.\/:-]//g; $s ne "" ? qq("$s") : "null" };
  my @items = map {
    sprintf(q({"name":"%s","base_min":%s,"head_min":%s,"ratio":%s,"ceiling_ms":%d,"runs":%d,"verdict":"%s"}),
      $_->{name}, $num->($_->{base}), $num->($_->{head}), $num->($_->{ratio}), $_->{ceiling}, $_->{runs}, $_->{verdict})
  } @rows;
  printf qq({"skipped":false,"ok":%s,"base":%s,"base_ref":%s,"base_ref_date":%s,"limit_ratio":%.2f,"limit_ms":%d,"commands":[%s]}\n),
    $ok ? "true" : "false", $str->($sha), $str->($ref), $str->($ref_date), $RATIO, $FLOOR_MS, join(",", @items);
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

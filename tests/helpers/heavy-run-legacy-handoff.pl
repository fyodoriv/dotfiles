use strict;
use warnings;
use Fcntl qw(:flock);
use File::Path qw(make_path);
use IO::Handle ();
use POSIX qw(WNOHANG);
use Time::HiRes qw(time sleep);

sub write_file {
    my ($path, $body) = @_;
    open(my $file, ">", $path) or die $!;
    print $file $body;
    close($file) or die $!;
}

sub read_file {
    my ($path) = @_;
    open(my $file, "<", $path) or die $!;
    local $/;
    return scalar <$file>;
}

sub await {
    my ($ready, $description) = @_;
    my $deadline = time() + 15;
    until ($ready->()) {
        die "Timed out waiting for $description\n" if time() >= $deadline;
        sleep(0.05);
    }
}

my ($source, $state, $fixture) = @ARGV;
die "Expected a disposable queue\n" unless $state eq $ENV{HEAVY_RUN_DIR}
    && $state eq "$ENV{BATS_TEST_TMPDIR}/hr" && $fixture eq "$ENV{BATS_TEST_TMPDIR}/handoff";
umask 077;
make_path($fixture, "$state/queue", "$state/slots");
my $code = read_file($source);
my $begin = index($code, "  sub tick {\n");
my $scan = index($code, '    opendir(my $qd, $queue) or return;', $begin);
die "Scheduler scan changed\n" unless $begin >= 0 && $scan > $begin;
substr($code, $scan, 0) = <<'PERL';
    my $handoff_fixture = $ENV{HEAVY_RUN_HANDOFF_FIXTURE};
    my $handoff_tick = !-e "$handoff_fixture/before-scan";
    if ($handoff_tick) {
      put("$handoff_fixture/before-scan", "ready\n") or die "Could not mark scheduler scan\n";
      my $deadline = Time::HiRes::time() + 15;
      until (-e "$handoff_fixture/legacy-held") {
        die "Timed out waiting for legacy handoff\n" if Time::HiRes::time() >= $deadline;
        select(undef, undef, undef, 0.05);
      }
    }
PERL
my $after = index($code, "    # Pause marks:", $scan);
die "Scheduler decision boundary changed\n" unless $after > $scan;
substr($code, $after, 0) = <<'PERL';
    if ($handoff_tick) {
      my $reason = read1("$queue/$name.why");
      my $grant = read1("$queue/$name.grant");
      put("$handoff_fixture/decision", "$reason\n$grant\n") or die "Could not mark scheduler decision\n";
    }
PERL
my $scheduler = "$fixture/scheduler";
write_file($scheduler, $code);
chmod(0700, $scheduler) or die $!;

my $name = sprintf("%010d-%d", 1, $$);
my $ticket = "$state/queue/$name";
open(my $waiting, ">", $ticket) or die $!;
flock($waiting, LOCK_EX | LOCK_NB) or die $!;
print $waiting "pid=$$ cwd=fixture cmd=legacy\nwait=waiting\nproject=fixture-old\n";
$waiting->flush or die $!;
write_file("$state/gate-open", "$name\n");

my $child = fork();
die "Could not start scratch scheduler: $!\n" unless defined $child;
if ($child == 0) {
    close($waiting);
    $ENV{HEAVY_RUN_HANDOFF_FIXTURE} = $fixture;
    $ENV{HEAVY_RUN_WAIT_LOG} = "$state/waits.log";
    exec($scheduler, "/bin/sh", "-c", 'printf "young\n" >> "$1"', "fixture", "$fixture/ran") or die $!;
}

my ($domain, $slot, $decision, $early);
eval {
    await(sub { -e "$fixture/before-scan" }, "scheduler scan");
    open($domain, ">>", "$state/lock") or die $!;
    flock($domain, LOCK_SH | LOCK_NB) or die $!;
    open($slot, ">>", "$state/slots/1") or die $!;
    flock($slot, LOCK_EX | LOCK_NB) or die $!;
    write_file("$state/slots/1.owner", "00:00:00 pid=$$ cwd=fixture cmd=legacy\nproject=fixture-old\nstart=1\n");
    unlink($ticket) or die $!;
    close($waiting) or die $!;
    write_file("$fixture/legacy-held", "held\n");
    await(sub { -e "$fixture/decision" }, "scheduler decision");
    $decision = read_file("$fixture/decision");
    $early = -e "$fixture/ran";
};
my $fixture_error = $@;
close($slot) if defined $slot;
close($domain) if defined $domain;
if ($fixture_error) {
    kill("TERM", $child);
    waitpid($child, 0);
    die $fixture_error;
}
my $status;
eval {
    await(sub {
        return 0 if waitpid($child, WNOHANG) == 0;
        $status = $?;
        return 1;
    }, "younger command after slot release");
};
if ($@) {
    my $error = $@;
    kill("TERM", $child);
    waitpid($child, 0);
    die $error;
}
die "Younger command failed after slot release\n" unless $status == 0;
die "Expected one younger command\n" unless read_file("$fixture/ran") eq "young\n";
my ($reason, $grant) = split(/\n/, $decision, -1);
die "Expected busy reason and no grant while the legacy slot was held; received reason '$reason', grant '$grant'\n"
    unless $reason eq "no free slot (1/1 busy)" && $grant eq "" && !$early;
print "Observed the legacy slot before grant; younger command ran once after release.\n";

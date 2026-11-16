package Time::HiRes;
# A virtual clock for tests/perf-gate.bats. It stands in for Time::HiRes when
# the test puts this folder first in @INC (through PERF_GATE_PERL). Its time is
# a fixed start plus the seconds that fixture tools wrote to the file named by
# PERF_GATE_FAKE_CLOCK. A fixture tool "takes" N seconds by appending N to that
# file, so every measured duration is exact and no wall clock decides a verdict.
use strict; use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(time sleep usleep);
my $clock = $ENV{PERF_GATE_FAKE_CLOCK};
my $start = CORE::time();
sub time {
  my $sum = 0;
  if (defined $clock && open(my $fh, "<", $clock)) {
    while (my $line = <$fh>) { $sum += $line if $line =~ /^[0-9.]+$/; }
    close $fh;
  }
  return $start + $sum;
}
sub sleep { CORE::sleep(int($_[0] + 0.999)) }
sub usleep { select(undef, undef, undef, $_[0] / 1e6) }
1;

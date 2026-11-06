# Glove80 private-log race test

Draft #492 needs a descriptor-relative log writer. Its previous pathname
checks do not prove safety if a directory changes between check and open.

Goal: prevent a scratch directory replacement from redirecting a log write.
Question: can a deterministic test replace the pathname after its directory
descriptor is opened and verify that a sentinel directory stays unchanged?

Measurement: `heavy-run bats tests/glove80-private-log.bats`. First land this
test harness without a writer. Its default run reports skips; setting
`GLOVE80_REQUIRE_LOG_HELPER=1` makes the missing helper fail. After a separate
implementation, success requires both the ordinary private append and the
directory-replacement control to pass without skips. The swap callback checks
the opened directory descriptor's device and inode first. The test requires
coreutils `gtimeout` and fails on a watchdog termination. Any sentinel change,
incorrect mode, or missing control rejects the approach. Existing Glove80
tests and a fresh full gate remain required. This test proves only the fixed
scratch scenario, not safety against every filesystem or attacker.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; the independent review of #492.

# Register synthetic read-failure control

The directory-input control in `b4fde5a` was inconclusive. Python exits during
startup when stdin is a directory, before the model can catch the read error.
The 32-case run recorded 31 passes and this setup failure. Its log is private.

Goal: measure how the model handles a read error after interpreter startup.
Question: when a test-owned reader raises `OSError`, does the actual model
return `fallback` without dispatch? Predict 1/1 fallback, exit zero, a canary
showing exactly one read with the 65,537-byte bound, and zero dispatch. The
first 31 cases must continue to pass. Measure with
`JOBS=1 heavy-run bats tests/heavy-run-discovery-json.bats`: exactly 32 named,
ordered passes, no skips or TODOs. Before the fix, run the named N30 alone and
require it to fail because the model does not catch the injected read error.

Use a clean isolated Python harness with normal stdin. Replace `sys.stdin` in
that process with a test-owned reader, then run the actual model file as
`__main__`. The reader records its call and raises a fixed synthetic `OSError`;
the harness does not catch it or print the expected result. Confirm the call
bound and the existing dispatch and startup canaries. If any of the 32 cases,
canaries or the fresh repository gate fails, abandon this approach. Setup
failure is inconclusive and requires another design. Independently review.

This tests model exception handling after Python starts. It does not establish
behavior for operating-system pipe failures, Python startup failures, executor
parity or the production guard.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.

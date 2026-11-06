# Git doctor per-machine email allowance

Issue #478 asks for an explicit per-machine allowance without weakening public
push protection. The existing doctor skip stores one check ID on that machine;
it is a check-wide opt-out, not an allowance bound to a specific email.

Goal: make the existing route clear and verify its safety boundary. Question:
can a configured synthetic private email be skipped in the doctor while the
independent public push guard still rejects it? Predict one skip and one guard
refusal, with zero leaked email values in the doctor output.

Measurement: `heavy-run bats tests/git-doctor-email-allowance.bats`. Success
requires the conditional ID to be registered, the local override to produce a
skip rather than a failure, and the synthetic public push to be refused.
Any missing ID, failed opt-out, identity disclosure or allowed push rejects
this approach. Document that the opt-out applies to future identities too.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #478 and the existing doctor override API.

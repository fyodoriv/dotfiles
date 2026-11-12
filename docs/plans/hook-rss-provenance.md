# Hook memory baseline provenance prediction

Registered before implementing or running a replacement measurement on
2026-11-11. The first two-window observation had equal positive medians, but
its retained data did not bind the receipt to the exclusive queue admission or
establish all effective inputs. It is provisional and cannot qualify gate G.

Hypothesis: a fixed, reviewed harness can bind one installed-Mac invocation to
its own exclusive `heavy-run` admission and detect changes in the enumerated
source and tool inputs without printing private paths, environment values or
hashes. The original 15-sample windows, 0.95–1.05 A/A floor and 1.10 candidate
memory bound remain unchanged.

Measurement: keep a unique private run directory and wait log. Record a random
run ID, the harness digest and parent identity privately. Require
`HEAVY_RUN_SLOT=exclusive` and exactly one matching parent/slot admission in
the private wait log. Verify the installed checkout, pinned tracked hook and
bootstrap sources, and the fixed harness before and after. Independently audit
the exact status-command path and snapshot effective bootstrap tool selections
and their file identities before and after. Record only bounded validity flags
and positive numeric samples in the shareable receipt; do not print raw paths,
environment, arguments or private hashes.
The tracked launcher is included in the source check. The selected Perl and
both shell startup files are checked before and after. The caller supplies
private expected SHA-256 values for both startup files; neither value is
printed or written to the receipt.

Take two windows of 15 samples using the registered input and the same
`bash`/`exec` timing wrapper. Reject missing samples, nonempty hook output,
changed enumerated inputs, missing admission, or load above the logical CPU
count at any window boundary. The median ratio must be 0.95–1.05. Run through
the normal Mac-wide `heavy-run --exclusive` queue, never a private replacement
queue. A later candidate uses the same method and compares its median with
the lower qualifying baseline median.

Success: 30 valid samples, exact admission binding, stable enumerated inputs,
valid load checks, ratio in range and independent review. Pivot: any unknown
identity, failed validity condition, unsafe output or mismatched admission is
inconclusive; keep the old hook. Before/after observations cannot prove that
an input did not change and revert or that unrelated OS work did not overlap.
The receipt qualifies only its explicitly observed boundaries; it does not
prove a port, full process isolation or real-world speedup. Admission is a
correlation with a trusted `heavy-run` launcher and its private log, not an
independent kernel attestation of the lock owner.

The receipt code alone does not qualify a live timing. Before one, separately
review a trusted launch procedure that creates an empty private wait log,
invokes the absolute tracked launcher, and binds its selected Perl and child
relationship. Independently bind the expected startup-file digests to the
audited files. Caller-supplied values alone do not establish that binding.

The [retained-provenance contract](hook-retained-provenance-prediction.md)
requires a caller-selected private run ID and independently retained expected
revision and audit bytes. The verifier recomputes the sample medians and A/A
ratio. Load and source/tool flags remain assertions from the measurement
process; the retained files do not independently reconstruct those inputs.

Anchor: `rust-hook-status-experiment.md`, `rust-agent-hooks`, the heavy-run
queue contract, Basili, Caldiera and Rombach 1994 (GQM), and Munafò et al.
2017 (pre-registration).

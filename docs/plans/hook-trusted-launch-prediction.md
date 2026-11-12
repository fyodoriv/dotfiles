# Hook timing launch provenance prediction

Registered before implementing the trusted launcher on 2026-11-12. The receipt
harness checks its parent against a wait-log row, but does not prove which
launcher or Perl executable created it. The first memory observation remains
provisional.

Hypothesis: a reviewed launcher can tie an initially empty, private wait log to
one direct invocation of the pinned absolute `heavy-run` file and correlate the
receipt parent with that invocation, while checking the selected Perl and
independently audited shell startup files without disclosing their identities.

Measurement: use synthetic launcher and receipt fixtures, never the live queue,
to plant a wrong launcher, pre-existing log, altered executable, wrong parent,
changed startup digest, nested queue marker, and nonexclusive admission. Verify
no timed child starts in each rejected case. Include a private canary in a
failure case. A synthetic pre-timing handshake must reject a wrong parent
before it can start the synthetic timed child. Check one valid fixture end to
end, then request independent review before any live timing.

The child first writes its own private PID record, then replaces itself with
the absolute launcher. This keeps the PID stable and ensures a record-creation
error occurs before the child enters the shared queue. The receipt checks the
record before any timed sample.

Interruption correction, registered before changing the wait logic: an
interruption must not terminate the queue owner while its sample may still be
running. A synthetic controller receives a process-group interruption while
its queue owner and sample run in a separate session. Success requires the
sample to finish before the queue owner exits, with no
signal sent to the sample. The launch result stays inconclusive. Pivot if this
cannot be shown with owned fixture processes. Interruption may wait for an
already queued or running fixture to finish. Direct signals to the queue owner
and forced process death remain unproved boundaries.

Success: the valid fixture passes, all seven planted invalid cases fail closed,
no rejected case starts a timed child, and zero private canaries or digests
appear in public output. The resulting evidence is a trusted-launch correlation,
not independent kernel attestation or proof that inputs never changed and
reverted. Pivot: an unbindable process relationship, unknown shell startup, or
unsafe output leaves the baseline inconclusive and retains the existing hook.

Anchor: `hook-rss-provenance.md`, independent timing review, Basili, Caldiera
and Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).

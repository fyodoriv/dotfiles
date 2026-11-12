# Hook retained-provenance prediction

Registered before implementation on 2026-11-12. An exclusive 15+15 run passed
its internal checks, but its receipt and separate launch log did not retain an
independent link to the revision, private audit and launcher verdict. Its equal
medians remain provisional.

Hypothesis: one owner-only launch record can bind the exact run ID, source
revision, canonical private audit identity, exclusive parent, wait log, receipt
bytes and final verdict. An independent reader can then check that association
without publishing paths, process identifiers, environment values or hashes.

Measurement: synthetic fixtures create and verify the private record. Plant
wrong revision, audit, parent, wait log, receipt, run ID and verdict; also plant
missing, duplicate, malformed and non-private records and a private canary.
Require every altered association to fail and every valid fixture to pass.
Review the format and tests independently, then use hosted CI. A new live
baseline requires a fresh independent audit and its own exclusive admission.

Success: all registered synthetic mutations fail closed, the valid fixture
passes, private fields and canaries never enter public output, and independent
review confirms the retained link. Pivot: any missing association, ambiguous
file or disclosure leaves the old and new observations provisional. The record
is a trusted local correlation, not kernel lock attestation or proof against
transient changes and same-user tampering.

Before launch, an exclusive private intent records the run ID, revision and
digest of the exact reviewed audit bytes. After postflight, a separate private
final record binds that intent, parent record, wait log and receipt bytes. A
verifier receives the expected revision and audit bytes independently, rejects
duplicate keys and unsafe files, and recomputes the numeric sample checks. It
does not claim crash durability or that an unkeyed record proves the controller
ran. Incomplete records remain inconclusive.

The caller chooses and privately retains a fresh 128-bit run ID before
invocation. The launcher reserves its run directory exclusively before the
worker starts. A later verifier requires that independently retained ID,
revision and audit bytes. Reuse of an existing run directory is rejected.

Anchor: `hook-rss-provenance.md`, the independent 2026-11-12 run review,
Basili, Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017
(pre-registration).

# Hook candidate observation prediction

Registered before building the candidate measurement on 2026-11-12.

Hypothesis: a candidate-specific, private observation can measure the
registered status fast path without treating the earlier baseline's source
closure as proof of the new helper. It can reject missing, changed or
unverified inputs before making a performance claim.

Measurement: under exclusive `heavy-run` admissions, measure two windows of
15 candidate peak-RSS samples using the registered payload, direct source path
and wrapper, and four separate
sets of 15 order-balanced old/candidate timing pairs. Check status, stdout and
stderr parity for each pair. Record all samples privately. Separately run the
unchanged registered performance gate.

Alternate the first version within each case. Start cases one and three with
the old version, and cases two and four with the candidate. This yields 30
old-first and 30 candidate-first pairs across the four cases.

Before use, independently review the exact launcher, harness, startup files,
effective tool selections and scratch installation. Bind private intent,
admission, wait and receipt records to a fresh caller-selected run ID, pinned
source revisions and the audit. Check source, tools, relevant installed link
text and targets, and host load before and after. Candidate closure includes
the hook, literal-status helper, bootstrap, endpoint-path helper, installer,
launcher, wrapper and harness; old closure is pinned separately. Refuse dirty,
untracked, missing, altered or unverifiable effective inputs. Handle
interruption so no sample outlives its queue owner. This is trusted local
correlation, not kernel attestation or protection from same-user interference.

Success: exactly two windows of 15 positive candidate RSS samples, agreeing
within the baseline's 0.95–1.05 A/A range, and 15 valid timing pairs
for each of the four preregistered status cases; zero parity failures; all
input, admission and noise checks pass. Candidate RSS median is at most
5,262,540 bytes; each timing median ratio is at most 0.80; the unchanged gate
row ratio is at most 0.50. All must pass. Keep raw data private.

Pivot: missing samples, changed inputs, failed parity or contaminated runs are
inconclusive. A valid threshold failure retains the old hook. Do not promote a
checkout-only result as proof of installed behavior. Reuse the earlier qualified
baseline only for its original old-source closure; do not claim it measured
the candidate helper.

Anchor: [hook status experiment](rust-hook-status-experiment.md) and
[trusted launch](hook-rss-provenance.md).

## Retained publication protocol

Registered before implementation. Verify the private pending record first.
Publish by creating an exclusive hard link named `launch.json` to that record.
Keep both names as intentional evidence. The link creation is the publication
point; do not remove either name as cleanup. The reader must verify two stable,
owner-only no-follow handles for the same inode and exactly two links. A
pending-only prepublication check requires one link.

Success: pending-only, complete two-link and every planted missing, extra,
changed, unsafe or mismatched-link case produce the expected decision. A crash
after publication can leave the controller exit status unknown; publication
does not prove a normal exit. The protocol does not claim fsync durability or
protection from same-user tampering. Any unverified or partial pair is
inconclusive.

## Fixture input boundary

The preparation worker checks the private intent and manifest digest before it
reads the fixed source snapshot and creates the scratch hook links. It is not a runnable worker. Before wiring
it into one, independently review its exclusive scratch reservation, held
directory handles, no-follow writes and rejection of partial fixtures. A scratch
fixture does not prove installed behavior: bootstrap can still select helpers
and executables from the live installation and home directory. Audit those
choices and their unchanged inputs before collecting any timing samples.

## Scratch write prediction

Hypothesis: an exclusively created scratch child and directory-relative,
no-follow writes prevent fixture preparation from redirecting writes outside
the private run. Measurement: `python3 tests/hook_pair_worker_test.py` with
planted existing directories, links, replaced entries and write failures.
Success: every planted redirect is rejected, zero outside files change, and
both sides match the verified snapshot. Pivot: any uncontained write or
unverifiable partial fixture blocks worker integration. The scratch snapshot
must be rechecked before and after capture. Anchor: the fixture input boundary
and trusted-local-correlation limits above.

## Remote source mapping prediction

Hypothesis: the public GitHub Git data API can supply an independently
reviewable commit-to-blob mapping without a local Git object reader. Trust the
GitHub HTTPS API as the remote source; its JSON is not cryptographic proof of
the commit object. Measurement: focused mapping-parser tests with exact commit
and tree responses, missing or duplicate paths, wrong hashes, types, modes,
truncation and malformed records. Success: all nine expected entries resolve
to exact blob IDs and modes for the two full revisions, and every planted
invalid response is rejected. Pivot: unavailable, oversized, ambiguous or
unverifiable responses leave the mapping inconclusive and block timing.

Fetch only the fixed public repository and exact commit and tree IDs. Use
non-recursive trees, system-trust TLS, disabled proxies, restricted hosts and
redirects, bounded response sizes and socket inactivity timeouts. A final
over-limit detection read can consume one extra byte, then stops the fetcher. Send no
local paths or credentials.
Retain the reviewed mapping and response provenance privately and bind it to
the run and source audit. Compare each mapped blob with the bounded local
source snapshot. DNS, slow streams and filesystem operations can defeat a strict wall-time
bound; the inactivity timeout is not a total deadline. This does not establish checkout HEAD, installed behavior,
tool closure or protection against transient same-user changes. Anchor:
[object-reader pivot](hook-object-reader-pivot.md).

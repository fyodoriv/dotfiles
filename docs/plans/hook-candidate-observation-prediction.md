# Hook candidate observation prediction

Registered before building the candidate measurement on 2026-11-12.

Hypothesis: a candidate-specific, private observation can measure the
registered status fast path without treating the earlier baseline's source
closure as proof of the new helper. It can reject missing, changed or
unverified inputs before making a performance claim.

Measurement: under exclusive `heavy-run` admissions, measure two windows of
15 candidate peak-RSS samples using the registered payload, direct source path
and wrapper, and four separate
sets of 15 order-balanced old/candidate timing pairs. The preparation helper
constructs the four fixed JSON payloads; the plain case matches the RSS gate
payload byte for byte. Check status, stdout and stderr parity for each pair. Record all samples privately. Separately run the
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

Before fetch, reserve a private request with the independently chosen run ID,
exact revisions, fixed origin, limits and audited directory identity. Retain
its digest independently. The preparation controller checks this request
before and after collection and before accepting the archive. Its injectable
fetch callback is test-only and does not establish network provenance. A
separate entry point constructs the restricted fetcher with the registered
limits; independently review its exact inputs before live use. The request is
correlation evidence, not proof of origin. Fetch only the fixed public repository and exact commit
and tree IDs. Use
non-recursive trees, system-trust TLS, disabled proxies, restricted hosts and
redirects, bounded response sizes and socket inactivity timeouts. A final
over-limit detection read can consume one extra byte, then stops the fetcher. Send no
local paths or credentials.
Retain the reviewed mapping and response provenance privately and bind it to
the run and source audit. A standalone verifier checks the independent audit
and archive digests, then compares all manifest modes and blob IDs. It is not
a source-byte or origin check. The preparation launcher and final verifier
require this binding, retain the archive and bind its digest in intent. The
non-runnable worker checks that digest at preflight; it still needs to recheck
the archive after capture. The independent audit must establish origin and
check the actual source bytes. The archive writer
requires an independently supplied directory identity, uses exclusive creation
and checks readback.
A failed write leaves an unusable partial file; never derive an accepted digest
from it or overwrite it. The archive origin field is not proof of acquisition.
Compare each mapped blob with the bounded local source snapshot. DNS, slow
streams and filesystem operations can defeat a strict wall-time bound; the
inactivity timeout is not a total deadline. This does not establish checkout
HEAD, installed behavior,
tool closure or protection against transient same-user changes. Anchor:
[object-reader pivot](hook-object-reader-pivot.md).

## Acquisition provenance correction

The first retained archive replayed but its result held only the archive
digest. It did not bind that archive to the reviewed invocation, request and
runtime audit. Treat it as inconclusive. Do not retrofit that missing link.

Before a new fetch, retain a fresh request and independently review the exact
invocation and runtime audit. A successful result must bind the archive digest
to the request, control, invocation, runtime audit and independent pre-use
review. Recheck those inputs after collection and before publishing the
result. A separate reviewer then verifies the retained links and replays the
records. Any missing, changed or ambiguous link is inconclusive. This remains
trusted local correlation, not protection from same-user interference or a
cryptographic proof of remote origin.

## Run-directory locality prediction

Hypothesis: checking the opened run directory's filesystem after reservation
will reject a nonlocal or unverified destination before source acquisition.
Measurement: focused synthetic local/nonlocal/error cases, followed by an
independent audit of the macOS filesystem API. Success: every local fixture
is admitted and every nonlocal, unsupported or failed check is rejected.
Pivot: an unknown ABI, unavailable flag or mismatch blocks the measurement;
do not infer locality from the parent alone. The preparation guard defaults
to rejection and accepts only a caller-audited inspector; no real macOS
inspector is implemented yet. When the worker is ready, prefer a small
adapter built against macOS headers over a handwritten filesystem structure.
Audit its source, binary, ABI and load path, and test local, nonlocal and error
outcomes. Check again after capture before qualifying a run. This check does not prove durability or prevent transient same-user changes. Anchor: the source-audit
local-filesystem assertion above.

## Effective tool closure review

The four literal status cases use the selected `dirname` and `cat`, absolute
`plutil`, and the bootstrap's conditional path and helper resolution. The old
hook also probes for `rg`. The existing tool snapshot captures many selected
paths, candidates, startup files and boundary states, but does not prove which
live endpoint helper the hook actually sources. It also does not bind every
shebang interpreter or intermediate symlink of selected wrappers.

Before capture, bind the hook-resolved dotfiles root and live endpoint helper
to the independently audited source, including fallback and absence cases.
The preparation worker can compare that helper with its verified source
snapshot. Before live use, derive the root identity from the independently
retained audit and check the environment after shell startup. Audit actual
selected wrappers and their interpreter chains. Recheck the effective inputs
after capture. Boundary checks do not prove that inputs were
unchanged between them. The existing snapshot probe itself starts Bash,
executes startup and bootstrap code, and may run selected tools. It has no
qualified timeout or descendant cleanup and does not report the resolved
helper path. Do not treat it as a passive or bounded audit. An unresolved
selection or dependency blocks timing.

## Effective endpoint helper prediction

Hypothesis: requiring the configured installed root and its exact audited
endpoint helper rejects bootstrap fallback or substitution before capture.
Measurement: focused synthetic controls for the configured root, missing or
changed bin directory, helper bytes, modes, links and directory identities.
Success: the exact audited helper is accepted; every planted missing, changed,
linked or fallback case is rejected, with zero fallback behavior changed in
the hook itself. Pivot: any unresolved selection, unsafe path or mismatch
blocks timing. This binds only the helper; wrapper interpreters and system
dependencies still need independent review. Anchor: the effective tool
closure review above.

## Owned-child capture prediction

Hypothesis: one direct owned child per sample, bounded stream draining and
deferred ordinary interruption can preserve the queue slot and partial
evidence without signaling an unowned process. Measurement: pure injected
process, stream, clock and receipt tests for start, output, wait, interruption
and persistence failures. Success: zero next samples after an invalid event,
zero unbounded retained output, zero signals sent by the worker, and every
completed attempt persisted before continuation. Pivot: any unverified child
or failed cleanup makes the run inconclusive; do not start a live benchmark.

Install handlers for ordinary INT, TERM and HUP before starting the owned
child. They only mark interruption. Retain at most 4,096 bytes per output
stream and drain any excess without keeping it; any excess invalidates the
sample. The preparation accumulator bounds retained bytes only. The future
selector must also bound each read, continue draining after overflow and prove
stream completion; an empty buffer alone is not proof. Reap that direct child, retain its invalid attempt and run postflight. Direct
child exit and pipe EOF do not prove that all descendants have exited. Do not
start a live paired worker until independently reviewed containment or an
equally strong proof establishes that no sample can outlive its queue owner.
If cleanup is uncertain after launch, do not voluntarily release the slot;
indefinite waiting may be necessary. Hard kill, parent death and host failure
remain outside this protocol's control.
Physical interruption or descendant tests require separate preregistration
and an independent safety review. Anchor: the retained publication and
observation controls above.

The lifecycle review found that direct-child wait, pipe EOF and a new process
group cannot by themselves prove that descendants have exited. A descendant
can close its pipes or leave a group. Do not weaken the original no-outliving
requirement or treat the bounded-output preparation as a completed lifecycle.

Apple's [background-process guidance](https://developer.apple.com/documentation/appkit/managing-ongoing-background-processes-in-your-mac)
suggests XPC services for system-managed service lifetime. The reviewed
[XPC service documentation](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
does not state that arbitrary descendants are contained or finished when a
service ends. The [waitpid manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/waitpid.2.html)
describes waiting for child processes. From these sources, we cannot infer a
recursive descendant-completion guarantee. This is a bounded documentation
search, not proof that no other API exists.

## Unchanged gate pre-run review

A read-only review found that the current base cache is absent and the gate's
retention policy could remove an older marked cache entry. Its marker alone
does not establish that the entry is disposable current-session work. The
gate also waits for direct children without a reviewed descendant-completion
guarantee. Do not run it until both conditions are resolved. An isolated
cache would need a separately registered and validated comparison because
changing paths can affect timing. Earlier A/A results do not prove the
current run is safe or that the candidate meets the speed gate.

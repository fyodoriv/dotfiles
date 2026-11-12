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

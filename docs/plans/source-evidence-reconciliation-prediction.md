# Source evidence reconciliation prediction

Registered before implementing the join on 2026-11-12. The repository-wide
candidate index and earlier family receipts use different pinned revisions.
A source identity match is not an ownership or execution classification.

Hypothesis: joining the pinned candidate index to an explicit set of pinned
family receipts by exact path, blob and mode will distinguish current identity
matches from stale same-path evidence and candidates with no listed evidence,
without losing overlaps or assigning ownership.

Measurement: read the candidate index and the nine named family receipts from
one pinned Git revision. Validate each receipt's format and source records
against its own pinned source tree. Preserve all same-path matches, compare blob
and mode separately, and record exact, stale or absent evidence per candidate.
Reject duplicate paths, unsupported schemas, missing inputs and ambiguous source
identities. Regenerate byte for byte and plant identity, omission, duplicate,
staleness and overlapping-evidence errors. Run focused tests and hosted CI.

The inputs are the bin, library, doctor, scripts, root, Git-hook, agent-hook,
CI-script and source-ledger receipts named in the checker. Caller rows,
workflow snippets and generated outputs are not whole-file identity receipts.

Success: every indexed candidate appears once; every listed receipt source
record matches its own pinned tree; every same-path identity link is retained;
all planted errors are rejected; regeneration is byte identical. Pivot: any
ambiguous source, skipped input or false exact match leaves the join
unqualified. Exact identity does not establish ownership, execution, semantic
coverage, current checkout state or complete inventory.

Anchor: `tracked-source-candidates.json`, the family source receipts,
Basili, Caldiera and Rombach 1994 (GQM), and Munafò et al. 2017
(pre-registration).

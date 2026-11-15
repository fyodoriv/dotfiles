# Partial reviewed inventory ledger

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The reviewed boundary files record named cold-path exceptions. The committed
validator ledgers do not yet contain them.

**Hypothesis:** Copying each reviewed boundary into the existing ledgers makes
all reviewed identities available to the eventual audit without claiming
unreviewed source is complete.

**Measurement:** Hosted controls compare the ledger identities and
classifications with the reviewed records, reject a planted omission, and run
`migration-check inventory --check` against the committed tree.

**Success:** 100% of the reviewed boundaries match, the planted omission is
rejected, and the overall check exits nonzero while source reviews and
independent discovery are incomplete. **Pivot:** Any mismatch, accepted
omission, or successful incomplete check rejects the change.

The partial ledger is not a complete manifest. It contains no invented source
reviews, and it does not establish discovery coverage.

**Anchor:** `rust-source-inventory`; the source-bound boundary reviews;
Basili, Caldiera and Rombach 1994 (GQM).

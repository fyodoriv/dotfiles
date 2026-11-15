# Documentation paths in the inventory ledger

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The migration scope explicitly excludes documentation and prompts. The ledger
still lacks source-bound ownership records for documentation paths.

**Hypothesis:** Recording regular, non-shebang Markdown files under `docs/` as
out-of-scope documentation accounts for those paths without classifying an
executable-mode or shebang entry as inert.

**Measurement:** Hosted controls compare each eligible tracked path and Git
blob with both ledgers, reject a planted omission, and check that the overall
inventory still fails while other source reviews and discovery are incomplete.

**Success:** 100% of eligible documentation paths match; executable-mode and
shebang paths do not enter this group; the planted omission is rejected; and
the incomplete inventory check remains nonzero. **Pivot:** A mismatched path,
unsafe classification, or successful incomplete check rejects the change.

This is an explicit documentation scope decision, not proof about other file
forms, generated code or runtime behavior.

**Anchor:** The documentation exclusion in `rust-migration.md`, the partial
ledger, and Basili, Caldiera and Rombach 1994 (GQM).

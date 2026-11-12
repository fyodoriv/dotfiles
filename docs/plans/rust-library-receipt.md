# Library source receipt prediction

Registered before implementation on 2026-11-11. The source family is every
tracked Git blob under `lib/` at `57a4b14da82ad42c47bceebfc4e051d8bb9541d3`.
A read-only candidate found 63 paths. This receipt records file identity,
not caller reachability, ownership, generated output or complete interpreter
boundaries. The final manifest and validator remain separate work.

## Hypothesis and measurement

Extend the existing doctor receipt checker rather than create another inventory
engine. Add a library mode and a separate receipt with one selected exact source
anchor per file. Compare path, mode and blob to the pinned Git tree. Compare
anchor line and text to that same tree. Run
`python3 docs/plans/doctor-source-receipt-check.py --libraries` twice and
compare the output; run the existing doctor mode too.

For every file, plant removal, incorrect mode, incorrect blob, duplicate path,
and removal of its anchors. For every anchor, plant an out-of-range line,
wrong text, and a duplicate anchor. Each mutation runs alone. The checker must
reject every mutation and accept the unmodified receipt. The receipt must be
deterministic from the pinned source and checked independently.

## Success and pivot

Success: 63/63 pinned file identities match, every registered mutation is
rejected, both runs agree, and the existing doctor checker still passes. Zero
unreviewed lexical candidates are claimed as classified or executable.

Pivot: any accepted mutation, changed doctor result, nondeterministic receipt,
or unsupported completeness claim stops this design. Keep the source list as
an unverified candidate until the checker is corrected and independently reviewed.

Anchor: the existing `docs/plans/doctor-source-receipt-check.py`; Basili,
Caldiera and Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

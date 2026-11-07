# Register doctor-module source inventory

Dotfiles task `rust-source-inventory` needs evidence for executable families.
This slice covers tracked `modules/*/doctor.sh` files at immutable revision
`a846166aa1a14158cb6a5fef9a1c06ed3c0711f1`. It does not claim a complete
repository inventory, dynamic caller coverage, or the shared Rust validator.

Goal: establish a reviewable pinned source receipt. Question: does it account
for the entire selected family and refuse planted source-identity errors?
Predict all 33 selected paths match Git's mode and blob, every recorded source
anchor matches its exact line, and zero planted errors are accepted. Require
at least one reviewed executable/check boundary anchor per file. Record selected
source boundaries rather than claim they enumerate every dynamic edge.

After this prediction is committed, write a JSON receipt in
`docs/plans/doctor-source-receipt.json` containing only format version, pinned
revision, files (path, mode, blob), and anchors (path, one-based line, exact
text). Write a read-only validator at `docs/plans/doctor-source-receipt-check.py`.
It must compare the path set, mode and blob to `git ls-tree -r -z` for exactly
`modules/*/doctor.sh` at the frozen revision, get source bytes from `git show`,
reject duplicates, malformed data and invalid or missing anchors, and require
all 33 files to have anchors. It must test the real receipt and reject a
separate planted missing path, wrong blob, wrong mode, duplicate path, wrong
anchor line, wrong anchor text, missing all anchors for one file, and duplicate
anchor. Apply each applicable mutation to each file or anchor. It must use no
workspace or personal source content beyond pinned tracked Git objects, and
must not execute those objects.

Measurement, from the Dotfiles repo root after adding the two files:

```sh
python3 docs/plans/doctor-source-receipt-check.py
JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Require the validator to report 33/33 exact files, every recorded anchor
verified, every planted mutation rejected, and exit 0. Run it twice and compare
receipt bytes unchanged. An independent reviewer must read each selected source
and assess whether the selected anchors represent real executable/check
boundaries and identify omissions. Resolve all review findings and requalify the
final exact receipt and code; independent review does not convert selected
anchors into proof of complete caller coverage. The full repository gate and
public leak check must pass. Any missing file, accepted mutation, wrong anchor,
false coverage claim or gate regression rejects this method. Missing setup is
inconclusive. Freeze the revision and thresholds; do not drop a source or
mutation to obtain a pass.

Anchor: the existing `docs/plans/agent-hook-source-receipt.md` method;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.

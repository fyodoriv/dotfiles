# Tracked source candidate index prediction

Registered before implementing the index on 2026-11-12. Earlier receipts cover
selected families. They do not yet provide a repository-wide candidate list.

Hypothesis: a pinned union of tracked executable modes, selected source
suffixes and first-line shebangs will expose every tracked path matching that
explicit predicate, with one identity per path, for later ownership review.

Measurement: compare `git ls-tree` mode and blob records with a first-line
shebang search at one pinned revision. Record every matching path, mode, blob
and matching reasons. Regenerate byte for byte. Plant an omission, duplicate
and wrong blob for each candidate and require each to be rejected. Run the
focused test and hosted required gate.

The suffix set is `.sh`, `.bash`, `.zsh`, `.py`, `.pl`, `.awk`, `.rs`,
`.swift`, `.mjs`, `.cjs`, `.js`, `.ts`, `.tsx`, `.bats` and `.tmpl`.
The mode predicate is `100755`. The shebang predicate covers first-line
matches in Git's text search; binary content and symlink targets are not
followed. Modes and suffixes may still select such paths as candidates.

Success: all paths matching the three documented predicates appear once;
100% of planted omissions, duplicates and wrong blobs are rejected; and
regeneration matches byte for byte. Pivot: any missed predicate match,
ambiguous path or accepted planted error leaves the index unqualified.

The index does not prove that a candidate executes, identify its owner,
classify embedded code, find untracked or generated output, or establish that
nonmatching files contain no executable logic. Those remain inventory work.
Anchor: `rust-source-inventory`, the pinned Git tree, Basili, Caldiera and
Rombach 1994 (GQM), and Munafò et al. 2017 (pre-registration).

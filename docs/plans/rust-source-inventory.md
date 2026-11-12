# Dotfiles source inventory collection

The [source ledger](rust-source-inventory-evidence.json) records three reviewed
families at revision `24d7f41f65eb3c542553f41acacc07bf93619b45`.
This is the source-collection milestone of `rust-source-inventory`.
The task remains open for the rest of the repository and the pinned validator.

| Family | Tracked paths | Evidence |
| --- | ---: | --- |
| LaunchAgent templates | 27 | Installation conditions, generated plist destinations and source argv spans |
| Chezmoi lifecycle scripts | 30 | Source-state triggers, enablement and existing migration tasks |
| Native sources and build wrappers | 5 | Two Swift sources and three wrappers, including the generated ChromeWork applet |

The ledger keeps three native generated outputs separate from tracked paths.
It links the families without counting a template again when it calls a
script. References to other tracked files carry source blobs and remain
outside this reviewed slice.

The [stale lifecycle range receipt](stale-lifecycle-ranges.json) compares
three changed lifecycle sources with the ledger's earlier revision. Its
[registered check](stale-lifecycle-ranges-prediction.md) records six
line-alignment ranges without copying source text. Run
`python3 docs/plans/stale-lifecycle-ranges.py --check`. These ranges do not
establish semantic changes, runtime conditions, generated outputs or ownership.

An independent source review of those ranges found three changes at the
candidate revision `94eef66`:

- `run_after_claude-settings-env.sh` expands the desired environment object
  and adds a JSON-processing child call to its completion message. The existing
  settings update owns the write; the review did not inspect installed values.
- `run_onchange_brew.sh.tmpl` adds template conditions around an optional
  desktop package check and installation. An installation failure is reported
  without making it fatal.
- `run_onchange_launchagents.sh.tmpl` adds telemetry-related template helper
  calls and a generated condition that can skip agent installation. Template
  expressions in comments still execute when the template renders.

These are source-level relationships. They do not prove a template rendered,
a condition passed, a script ran, or an external change occurred. The earlier
ledger does not yet record the new relationships.

The [non-test classification receipt](non-test-source-classification.json)
reviews the 34 candidates outside `tests/` that were absent from the joined
receipts at candidate revision `94eef66`. It records 17 executable-source
candidates, 14 declarative or generated inputs, and three unresolved inputs.
Check the pinned identities and source spans with
`python3 docs/plans/non-test-source-classification.py --check`; the
[prediction](non-test-source-classification-prediction.md) gives the limits.
The checker verifies identity and line bounds. Independent source review
supports the categories; the checker does not infer them from the spans.
The categories do not establish ownership, execution, or generated output
behavior. The 383 absent test-tree candidates and six stale-only candidates
remain separate; this review does not complete the inventory.

The [stale hook and bin receipt](stale-hook-bin-ranges.json) compares the
other three stale-only paths with their earlier family receipts. It records
13 changed alignment ranges and the current match positions of 20 old
anchors. Check it with `python3 docs/plans/stale-hook-bin-ranges.py --check`.
Missing and ambiguous anchors stay unresolved; matching text does not prove
equivalent behavior or current caller coverage. The comparison is pinned to
the candidate revision and does not describe later source changes.

Independent source review found these changes in the compared ranges:

- The dangerous-Git hook expands its branch-command scanning and adds a
  constrained literal-search bypass. Review of the text does not prove that
  the bypass is safe for every input or that every caller runs the hook.
- The heavy-run hook adds limited command-lookup and Bats help/version
  exemptions, with conditions for nested or output-feeding commands. This is
  a caller-classification boundary, not proof of complete shell parsing.
- `kimi-goal` adds a directory precondition and changes how it selects the
  working directory before invoking its tool. This changes orchestration;
  source review does not establish the tool's external behavior.

These three executable candidates still need current boundary anchors,
parity and negative cases, and caller or installation evidence before a port
can be assessed. The range receipt alone does not establish ownership.

LaunchAgent property lists remain declarative config. Owned shell bodies
and native logic named in their arguments belong to the migration. The
two retired memory templates carry inactive relationships. Agentbrew owns
the current memory service.

A scratch fixture using chezmoi 2.73.3 ran a `run_at_login_*` source on both
applies. The name uses the normal `run_` prefix and does not schedule login
by itself. The endpoint bootstrap also has a distinct LaunchAgent caller.
[Chezmoi source-state attributes](https://www.chezmoi.io/reference/source-state-attributes/)

The collection regenerated byte for byte. Independent checks detected 65
omitted source or output records and 86 omitted source-derived relationships.
All 100 relationship records have verified source spans.

## Repository-wide source candidates

The [candidate index](tracked-source-candidates.json) records 744 paths at
revision `94eef66` that match executable mode, a listed source suffix or a
first-line shebang. The [registered predicate](tracked-source-candidates-prediction.md)
states the exact scope. Run `python3 docs/plans/tracked-source-candidates.py --check`
to regenerate the expected index and reject planted receipt errors.

This index includes overlaps with the family receipts. It is not an ownership
manifest or proof of execution. Embedded code, generated outputs, dynamic
callers, untracked files and nonmatching executable logic remain open.

The seven checkers listed in the [JSON type-safety prediction](source-receipt-json-types-prediction.md)
share a strict reader and type-sensitive comparison. They reject duplicate JSON
keys and boolean/number substitutions. This guards the receipts; it does not
change the scope of any source claim.

The [source evidence join](source-evidence-join.json) compares these candidates
with 11 pinned family receipts. At the indexed revision, 321 candidates have
at least one exact path, blob and mode match; six have only stale same-path
evidence; and 417 have no match in those receipts. The earlier nine-receipt
join had 305, 11 and 428 respectively. The [refresh prediction](source-evidence-refresh-prediction.md)
registered the expected change before the two new inputs were added. The join
retains stale links alongside exact links. The
[registered check](source-evidence-reconciliation-prediction.md) validates
the input identities and rejects planted receipt errors. Run
`python3 docs/plans/source-evidence-join.py --check`.

These counts describe correspondence with the listed receipts, not ownership,
execution, complete source coverage or the current working tree.

## Tooling-checkup skill scripts

The [tooling-checkup reference receipt](tooling-checkup-callers.json) pins the
11 skill scripts and 164 matching source lines across 26 paths at `3d3b904`.
The [registered search](tooling-checkup-callers-prediction.md) records literal
basename matches without copying line contents. Run
`python3 docs/plans/tooling-checkup-callers.py --check` to verify the receipt.
Matches can be documentation, tests or code. They do not prove execution,
dynamic calls, generated scripts or ownership.

## Tracked bin entrypoints

The [bin source receipt](rust-bin-source-inventory-evidence.json) pins every
tracked `bin/` entry at revision `a1928495a953055ff7db3d8f525d504faef2dc3a`.
All 130 Git blobs matched. The receipt also records seven Perl and AWK
invocation boundaries in `heavy-run`, `cached-run`, and `bats-affected`.
Each call has a definition anchor. The status command and controller
use the same Perl prelude with different bodies at their call sites.

Two runs produced byte-identical receipts. An independent check accepted the
original and rejected 140 planted omissions and wrong identities. This slice
records paths, entry interpreters, and selected embedded calls. A Bash
shebang alone cannot classify the code it launches. The native wrapper paths
can overlap the earlier ledger. Reconcile overlapping paths before counting
repository-wide coverage.

The [current bin identity receipt](rust-current-bin-source-receipt.json)
pins `bin/` at revision `c5ed285`; its [registered check](rust-current-bin-receipt.md)
records every tracked path, mode, blob and first line. Run
`python3 docs/plans/doctor-source-receipt-check.py --bin-sources`.

The [current boundary receipt](current-bin-boundaries.json) maps the seven
historical selected interpreter boundaries to pinned source at `0490b7b`.
The [registered check](current-bin-boundary-prediction.md) compares exact
definition and call lines, rejects planted errors and detects ambiguous
matches. Run `python3 docs/plans/current-bin-boundaries.py --check`. It does
not classify the full interpreter bodies, find other boundaries, or prove a
caller executes.

## Agent hook sources

The [agent-hook source receipt](agent-hook-source-receipt.json) pins the
tracked `agent-hooks/` family at the revision in its
[registered measurement](agent-hook-source-receipt.md). It records file
identities and selected exact source anchors. The selected boundaries include
the Perl body in the heavy-run hook and the jq filter used by the Git guard.
The endpoint-path scripts also source shared helpers or invoke managed shim
helpers. Independent review checked the source family; the receipt does not
claim every dynamic caller or semantic boundary is covered.

## Root source candidates

The [root source receipt](rust-root-source-receipt.json) records root-level
tracked blobs with executable mode, a shebang, or selected source suffixes at
revision `861c94f`. The [registered check](rust-root-source-receipt.md) pins
selected entry, helper and command anchors. Run
`python3 docs/plans/doctor-source-receipt-check.py --root-sources`. The bounded
predicate does not cover generated files or extensionless, non-executable
source without a shebang; it does not establish actual execution.

## Script sources

The [scripts receipt](rust-scripts-source-receipt.json) pins the tracked
`scripts/` files at revision `8a2cb8c`. Its selected entry, command-preparation and child-command
anchors are checked by the [registered receipt](rust-scripts-receipt.md).
Run `python3 docs/plans/doctor-source-receipt-check.py --scripts`. These
anchors do not establish complete embedded code, dynamic targets or execution.

## Git hook sources

The [Git hook receipt](rust-git-hook-source-receipt.json) pins the tracked
`git-hooks/` files at revision `81bcb68`. Its selected entry, helper, AWK and
delegation anchors are checked by the [registered receipt](rust-git-hook-receipt.md).
Run `python3 docs/plans/doctor-source-receipt-check.py --git-hooks`. These
anchors do not establish installed hook settings, downstream ownership or
complete executable behavior.

## CI script sources

The [CI source receipt](ci-source-inventory.json) pins the five tracked
`.github/scripts/` blobs and literal basename references in the pinned
Makefile and workflow files. The [registered check](ci-source-inventory-prediction.md)
regenerates the receipt and rejects planted errors. Run
`python3 docs/plans/ci-source-inventory.py --check`. Literal references do not
prove execution or cover dynamically constructed calls and embedded workflow
bodies.

The [workflow source receipt](workflow-source-inventory.json) records pinned
workflow identities and lexical `run:` candidates, including indented block
text. The [registered check](workflow-source-inventory-prediction.md) rejects
planted receipt errors. Run `python3 docs/plans/workflow-source-inventory.py --check`.
This is a lexical inventory aid, not a YAML parser or proof that a
candidate runs. Dynamic code and executable content outside the predicate
remain open.

## Library source identities

The [library source receipt](rust-library-source-receipt.json) pins all 63
tracked `lib/` blobs at revision `57a4b14`. Each path has a mode, blob and
first-line anchor. Regenerate it with
`python3 docs/plans/doctor-source-receipt-check.py --generate-libraries`.
The [registered check](rust-library-receipt.md) compares
them to that tree and plants identity and anchor errors. Run it with
`python3 docs/plans/doctor-source-receipt-check.py --libraries`.

This is an identity receipt, not a full caller or execution inventory. It does
not classify the libraries, establish dynamic calls, or account for generated
files. The manifest and pinned agentbrew validator remain open.

The [source-syntax receipt](rust-library-caller-receipt.json) records 277
matching lines from 123 tracked files at the same revision. Its
[registered check](rust-library-caller-receipt.md) covers a bounded lexical
search, including tests and templates. It does not establish that any line
executes, find dynamic names, or prove complete caller coverage. Run
`python3 docs/plans/doctor-source-receipt-check.py --library-callers`.

## Doctor module sources

The [doctor source receipt](doctor-source-receipt.json) pins the tracked
`modules/*/doctor.sh` family at its recorded Git revision. It records each
file's mode and blob plus one selected check or function boundary per file.
The read-only [receipt checker](doctor-source-receipt-check.py) compares the
receipt to the pinned tree and rejects planted identity and anchor errors.
Run it from the repository root:

```sh
python3 docs/plans/doctor-source-receipt-check.py
```

These anchors are entry points for review, not a full list of executable
boundaries or dynamic callers. The shared Rust validator is still required.

The [current doctor receipt](current-doctor-anchors.json) maps the same 33
selected historical anchor texts to source at `3d3b904`, including the five
doctor paths whose earlier identity evidence was stale. The
[registered check](current-doctor-anchors-prediction.md) validates both
historical and current blobs and requires one unique mapping per path. Run
`python3 docs/plans/doctor-source-receipt-check.py --current-doctor`. This does
not establish body equivalence, runtime execution or complete boundaries.

## Continue the inventory

Use the pinned Git blob IDs to compare the ledger with the current tree.
Review source changes before reusing a classification. Continue with owned
entrypoints, embedded interpreter bodies, generators and tests outside these
families.

When the shared Rust validator ships, convert these observations into its
file, component, generated-target and edge records. Use its observed call
receipts for executable boundaries. This ledger defines a source evidence
format only. It does not set the validator schema or satisfy the acceptance
gate in [the migration plan](rust-migration.md).

# Rust source classification (2026-11-15)

This closes step 4 (`rust-source-inventory`) of the
[Rust migration](rust-migration.md). Every tracked path now has one owner and
one of the five states. Embedded programs that the static scanner confirms
have their own records. The inventory check still fails closed, on purpose:
static scanning cannot prove that discovery is complete.

## Result

| Measure | Value |
|---|---:|
| Tracked paths with a review and a state | 2,234 of 2,234 |
| Unclassified paths | 0 |
| `ported` | 5 (Rust `app-priority` and its wrapper) |
| `exception` | 775, each naming a [Recorded exceptions](rust-migration.md#recorded-exceptions) row |
| `grandfathered` | 8 (the four pre-gate fixture crates) |
| `out-of-scope` | 1,446 (data, docs, vendored packages, shell and editor configuration) |
| Embedded programs recorded | 233 (93 from the five earlier boundary reviews, 140 new) |
| Shell files the scanner cannot parse | 369 (mostly `.bats` files and chezmoi templates) |
| Unresolved scanner findings | 14,784 (mostly dynamic arguments) |

Counts come from `python3 scripts/inventory-ledger.py --check`.

## How the ledgers are made

[`scripts/inventory-ledger.py`](../../scripts/inventory-ledger.py) rebuilds
`rust/migration-inventory/inventory.tsv` and `observations.tsv` from the
committed tree:

1. A path with an earlier reviewed record keeps that record's text. Only its
   blob id is refreshed.
2. A path without a record gets one from the script's ordered rules. Reviews
   made this way name the reviewer `rule-classification` and cite this file.
   - Regular Markdown under `docs/` and `.bats` files use the exact text that
     the document and Bats ledger tests rebuild.
   - Launchd templates, data, configuration and non-executable files are
     `out-of-scope`.
   - Shell and editor configuration (`home/`, `dot_config/`, `jetbrains/`,
     `vscode/`, symlinked dotfiles) is `out-of-scope`: shell that must stay
     shell.
   - Every executable maps, by path, to one recorded-exception slice (for
     example `bin/heavy-run` to `shared-queue` and `bin/gh` to
     `gh-public-write-safety`), to `ported` (app-priority), or to
     `grandfathered` (the four fixture crates).
3. The static shell scanner (`migration-check inventory --scan-shell`) runs
   on every tracked shell source. Each confirmed embedded program outside the
   five earlier reviews goes into
   [rust-embedded-discovery-review.json](rust-embedded-discovery-review.json)
   with the state of its file.

Run it after committing source changes, commit the result, and run it again
until `--check` reports `current` (the review JSON is itself a tracked file).

## Pivot crossed, and why the task still closed

The task's registered Pivot said that any blanket exception changes the
method to execution and caller analysis. Assigning exceptions by path rule
is close to a blanket exception, so that Pivot was crossed. The owner's
ruling on 2026-11-15 ("count some downsides as tasks and continue") is what
closes the task anyway. Caller analysis is the follow-up task below.

## What stays open

`migration-check inventory --check` now passes the source review step and
stops at `independent embedded and generated discovery remains incomplete`.
That gap is the recorded `embedded-discovery` exception in
[rust-migration.md](rust-migration.md#recorded-exceptions): 14,784 unresolved
findings and 369 unparsed shell files cannot be settled by static analysis.
Task `rust-inventory-dynamic-discovery` tracks it.

The ledgers pin blob ids, so each merge makes them stale. The daily
`.github/workflows/inventory-ledger-refresh.yml` job reruns the generator on
`feat/chezmoi` and pushes only the three generated files. Run it now with
`gh workflow run inventory-ledger-refresh.yml`.

The rules classify by path, not by reading callers. A new file lands in the
first matching rule. A wrong match is a one-line rule change plus a rerun.

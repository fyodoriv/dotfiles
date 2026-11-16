# Rust source classification (2026-11-15)

This closes step 4 (`rust-source-inventory`) of the
[Rust migration](rust-migration.md). Every tracked path now has one owner and
one of the five states. Embedded programs that the static scanner confirms
have their own records. The inventory check still fails closed, on purpose:
static scanning cannot prove that discovery is complete.

## Result

| Measure | Value |
|---|---:|
| Tracked paths with a review and a state | 2,238 of 2,238 (2,234 when first classified) |
| Unclassified paths | 0 |
| `ported` | 5 (Rust `app-priority` and its wrapper) |
| `exception` | 777, each naming a [Recorded exceptions](rust-migration.md#recorded-exceptions) row |
| `grandfathered` | 8 (the four pre-gate fixture crates) |
| `out-of-scope` | 1,448 (data, docs, vendored packages, shell and editor configuration) |
| Embedded programs recorded | 233 (93 from the five earlier boundary reviews, 140 new) |
| Shell files the scanner cannot parse | 371 (369 of them `.bats` files) |
| Unresolved scanner findings | 14,830 (almost all dynamic arguments in plain scripts) |

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

`migration-check inventory --check` passes the source review step and
stops at `independent embedded and generated discovery remains incomplete`.
That gap is the recorded `embedded-discovery` exception in
[rust-migration.md](rust-migration.md#recorded-exceptions): 14,830 unresolved
findings and 371 unparsed shell files.

Task `rust-inventory-dynamic-discovery` closed by its pivot on 2026-11-16.
The cheaper option ran first, on the tree at `ce60ef9`:

```sh
chezmoi execute-template --source . --file <template> > scratch/<name>.sh   # 14 shell templates
migration-check inventory --scan-shell <name>.sh --shfmt "$(command -v shfmt)"   # in a scratch git repo
```

| Measure | Raw templates | Rendered templates |
|---|---:|---:|
| Templates the scanner parses | 13 of 14 | 14 of 14 |
| Unresolved findings in the templates | 192 | 194 |

The whole tree stays at 14,830 unresolved findings (14,830 - 192 + 194 =
14,832, far above the 5,000 pivot line) and 370 unparsed files, 369 of them
`.bats`. Templates hold 1.3% of the findings. The rest are dynamic
arguments in plain scripts, so rendering cannot reach the line. Treating
`.bats` bodies as test tooling would clear the 369 unparsed files and leave
the unresolved count unchanged. Reopen only with a method that a
measurement shows will go below 500.

The ledgers pin blob ids, so each merge makes them stale. The daily
`.github/workflows/inventory-ledger-refresh.yml` job reruns the generator on
`feat/chezmoi` and pushes only the three generated files. Run it now with
`gh workflow run inventory-ledger-refresh.yml`.

The rules classify by path, not by reading callers. A new file lands in the
first matching rule. A wrong match is a one-line rule change plus a rerun.

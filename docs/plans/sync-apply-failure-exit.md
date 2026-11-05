# Sync apply failure prediction

Date: 2026-11-05
Source: dotfiles `547dcd6`; prediction sealed in private commit `d8d5d05c2d4be01a9d6b8ba7563263ff270ca81a` before test or production edits.

Goal: report a failed chezmoi apply as a failed sync.
Question: do canonical and applied-checkout callers preserve failure while retaining successful apply, clean skip, retry and lock cleanup?
Metric: four synthetic failure controls (canonical new control; existing applied error, applied record removal and canonical retry controls) must expect exit 1 instead of current exit 0. Failed routes emit no success footer and record one failed stats row. Canonical failure stops before local commit/push. Existing success and skip controls retain exit 0.
Hypothesis: preserving the helper's existing 0/applied, 1/failed, 2/skipped contract in both callers reduces false-success outcomes from 4/4 to 0/4. No helper or drift policy change is needed.
Measurement: from the isolated checkout, run `heavy-run env -u BASH_ENV -u ENV JOBS=1 bats tests/dotfiles-sync.bats` before and after the fix. The fixture uses scratch HOME/config/state, local Git remotes and fake chezmoi only; no real apply. Run final required `JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=` with normal admission, one worker and no capacity override.
Success: exactly four meaningful baseline failures and no setup errors; final exact file has zero failures, all four corrected failure outcomes, successful/skip paths exit 0, and required gate exits 0.
Pivot: any failure outside the four controls, unsafe scratch isolation, failure that still emits a success footer, lost retry/skip behavior or a nonzero required gate stops delivery. Inspect the assertion before changing the approach; do not weaken oracles or change unrelated pull/push policy.
Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric; Forsgren, Humble, Kim (2018), stability through reliable failure signals; existing `bin/dotfiles-sync` apply-helper return-status contract.

Implementation bounds: two caller status branches in bin/dotfiles-sync; exact Bats file, docs/multi-machine.md, this public plan and task lifecycle only. This is a surgical repair to an existing necessary-shell entrypoint, not a new shell engine.

## Evidence

The unchanged production baseline returned exit 0 for all four failure controls.
The four status assertions failed before the fix and passed after the two caller
changes, with no assertion edits. Successful apply, clean skip, retry, branch
safety and dry-run controls passed in both scoped runs.

The initial required invocation rejected Bats' parallelization flags with one
worker before starting tests. The serial command above is the repository's
documented one-worker recipe. Its first run exposed a launcher-selected Git
default-branch mismatch and this plan's volatile test totals. Base and candidate
reproduced the same remote-fixture failure with that Git selection. The corrected
launcher retains the owner's Git wrapper before adding build tools. Test oracles
stay unchanged; the failed receipts are retained.

On 2026-11-05, the documented serial required gate exited zero on code tree
`d1ae827c727e4b76b6f3eae976886eb5ea4a9ac7`, with the owner's Git wrapper
retained. The final evidence-text update is checked separately before delivery.

The fixtures use local Git remotes and fake chezmoi with scratch HOME, XDG config,
XDG state and lock paths. This establishes reporting behavior, not a successful
machine apply. The underlying apply failure remains separate. Required repository
checks must pass before delivery.

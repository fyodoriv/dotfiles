# Preserve owner-executable hooks during migration

## Problem and boundary

`dotfiles plugin migrate` drafts a manifest from a legacy overlay. Its hook
discovery requires all three execute permission bits. A private hook with
mode `0700` is executable by its owner but is omitted from the draft. The
hook runner uses the current user's executable check instead.

The unchanged default reproduces this under Bash 3.2 and Bash 5 with
`umask 077`. The existing migration fixture creates this mode. This is not
a shell-version failure. Do not relax the process mask or grant permissions
to other users to make discovery pass.

## Registered experiment

- **Goal**: preserve runnable hook capabilities when drafting a manifest.
- **Question**: does discovery follow the current user's execute access?
- **Hypothesis**: replacing the all-bits permission predicate with a portable
  current-user executable predicate reduces missed owner-executable hooks
  from 2 of 2 shell cases to 0 of 2. The predicate matches hook execution.
- **Measurement**: `heavy-run env JOBS=1 bats --filter 'migrate.*execute access' tests/plugin-v2.bats`, then the same command with `PATH="$PWD/tests/bash32:$PATH"` to use Bash 3.2. The test runs the real migration command on synthetic overlays with explicit modes `0700`, `0711`, `0755`, and `0600`.
- **Success**: 0 missed executable hooks in both shells; all 6 executable
  controls included; both non-executable controls omitted; migration exits
  0 in all 8 cases. Existing plugin suites and `make check` pass.
- **Pivot**: any missed executable or included non-executable control, or a
  failed migration, rejects this predicate. Revisit access semantics instead
  of changing fixture modes or weakening the thresholds.
- **Anchor**: Basili, Caldiera and Rombach 1994, Goal Question Metric;
  POSIX `test -x`, executable access for the current process:
  <https://pubs.opengroup.org/onlinepubs/9799919799/utilities/test.html>.

## Scope and lifecycle

Change only migration discovery, its regression test, and plugin migration
documentation. Overlay and draft state belong to one migration invocation.
Do not execute hook contents or change their permissions. Tests own and
remove their scratch overlays. Keep the shared heavy-job limit unchanged.

Register this plan before candidate code. Prove the new regression fails on
the unchanged discovery, then apply the smallest fix and verify both shells.

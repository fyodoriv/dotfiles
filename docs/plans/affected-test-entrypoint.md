# Affected test entry point

Issue [#636](https://github.com/fyodoriv/dotfiles/issues/636) asks
for a quick way to run the tests selected by changed files. Reuse the
current cached affected-test runner. Keep its exact test and path
mappings, and infer names only when those mappings have no result.

- **Hypothesis**: The new command selects tests for changed and
  untracked source files without sending unrelated tests to Bats.
- **Measurement**: Run hosted `bats tests/bats-affected.bats tests/makefile-bats-jobs.bats`.
  In scratch repositories compare the exact selected sets for a
  folder-prefixed test, a shortened name, an untracked file and a
  referenced path. Use the existing Make fixture to check the
  default and a chosen base through the real target.
- **Success**: All 4 selection controls return their exact test sets.
  Both base choices reach the same affected-test runner. Existing
  selector and Make controls pass with 0 missed references.
- **Pivot**: Reject after 1 missed test, 1 extra test in a fixed control,
  1 incorrect base or 1 regression in the full-suite target.
- **Anchor**: Issue #636 and the existing `bin/bats-affected` selector.

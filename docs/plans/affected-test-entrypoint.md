# Affected test entry point

Issue [#636](https://github.com/fyodoriv/dotfiles/issues/636) asks
for a quick way to run the tests selected by changed files. Reuse the
current cached affected-test runner. Keep existing targeted mappings.
Infer names when no targeted mapping applies and include literal
references in either case.

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

The [hosted selector baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44866545758/job/136731382137)
failed all three inferred name checks. The literal path reference passed.
A Make dry run reported that the requested target did not exist.

Before measuring the candidate, add three controls from independent review.
An explicit unknown base must return 2 before selection. An inferred
test and a test referring to the same source must both appear with its
exact path in `--pairs`. A new bin script with an inferred test must also
keep smoke coverage. Any missing test or changed dependency pair
invalidates the candidate.

The first candidate passed the new selection cases. Two existing checks
found compatibility gaps. The selector benchmark got a different list
in its default mode. The cache test looked for the Make recipe at its
old source location even though the expanded command kept its inputs.

Keep filename inference behind the new entry point. Require exact
default output parity and retain the existing benchmark threshold.
Check the expanded recipes for both affected-test targets. Require two
recipes with the selector's exact pairs, the HEAD cache key, and the
peer and doctor invocations. No additional file should match by name
in the selector's default mode.

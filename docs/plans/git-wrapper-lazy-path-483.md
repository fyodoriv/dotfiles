# Git wrapper: defer push-only path lookup (#483)

## Prediction before measurement

Goal: reduce wrapper overhead without changing Git selection, fallback,
streaming or push checks. Question: can the wrapper defer the directory
lookup used only by push authorization and cut added median time for two
common calls by at least 30% each?

Measure before and after from the repository root. The benchmark helper,
evaluator and focused tests will be added and committed before the baseline.
Use a fresh private directory from `mktemp -d` as `GIT_LAZY_EVIDENCE_DIR`;
the helper refuses to overwrite existing evidence. The helper
unsets `DOTFILES_REAL_GIT`, `DOTFILES_SYSTEM_GIT`,
`DOTFILES_PUBLIC_PUSH_ALLOWLIST` and `DOTFILES_PRIVATE_PUSH_ALLOWLIST` before
starting the timed commands. It requires `/usr/bin/git --version` to succeed;
the current wrapper then selects that binary. Use these exact commands:

```sh
export GIT_LAZY_EVIDENCE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/git-lazy-483.XXXXXX")"
heavy-run --exclusive bash docs/plans/git-wrapper-lazy-483-bench.sh before
heavy-run --exclusive bash docs/plans/git-wrapper-lazy-483-bench.sh after
heavy-run bats tests/git-wrapper-lazy-483.bats tests/git-wrapper.bats tests/public-push-allowlist.bats
python3 docs/plans/git-wrapper-lazy-483-evaluate.py "$GIT_LAZY_EVIDENCE_DIR/before.json" "$GIT_LAZY_EVIDENCE_DIR/after.json"
```

The helper runs `hyperfine --warmup 3 --runs 20` for, in order,
`/usr/bin/git --version`, `./bin/git --version`, `/usr/bin/git rev-parse
--git-dir`, and `./bin/git rev-parse --git-dir`, exporting before or after
JSON in that directory. It records the one-minute system load and logical CPU
count immediately before and after timing. A load above the CPU count at
either boundary invalidates that measurement. Report all raw medians and
standard deviations as well as the calculated differences and percentages.
Record the tested wrapper hashes and helper/evaluator hashes. Missing, stale,
incomplete or wrongly ordered output, failed commands, and invalid load at
either boundary of either measurement invalidate the comparison.

The focused Bats tests compare direct and wrapped stdout, stderr and exit
status for the two benchmarked calls and an ordinary failure. They compare
signal exit and output using a stub. They exercise real wrapper invocations
with stubbed Git for approved, denied and unresolved push targets, default
and overridden allowlists, a symlink invocation and a FIFO allowlist. No test
sends a network push. Keep the existing FIFO snapshot and cleanup in place.

For each pair, added time is wrapper median minus direct Git median. Baseline
added time must exceed 5 ms for both calls. Success requires at least 30%
lower added median time for each call, identical outputs and exits, and all
wrapper and push-allowlist tests passing. Any invalid measurement, improvement
below 30% for either call, or behavior failure abandons this approach. Do not
repeat the benchmark to select a favorable result. The exclusive scheduler
limits competing managed jobs; it does not control all machine activity.

This differs from the abandoned fast path: it retains the existing Git
candidate probe and exec/fallback behavior, and moves only path computation
that push authorization actually needs. It does not treat fetch as read-only
or claim a speedup for the whole application workload.

Anchor: [Goal Question Metric](https://doi.org/10.1002/9780470172669.ch12);
the earlier failed experiment is in [the prior plan](git-wrapper-read-fast-path-483.md).

## Baseline result and pivot

On 2026-11-06, the single baseline was invalid. Hyperfine 2.0.0 wrote its
measurements under a newer JSON schema, but the frozen helper expected the
older `times` and `median` fields. The helper rejected the output before it
saved the post-run load check. The safety harness passed before the
benchmark; no wrapper implementation was changed or measured after a fix.

The registered rule rejects an invalid measurement, so this approach is
abandoned without an after benchmark. Do not change the evaluator and repeat
this measurement to seek a pass. Private local evidence retains the raw
Hyperfine output, the frozen helper, evaluator and tests, and the safety-test
log. Those temporary scripts are not in this tree, so the registered commands
cannot be reproduced from this branch alone. Issue #483 remains open.

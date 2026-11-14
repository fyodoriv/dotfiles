# App-priority same-day experiment

The owner removed the seven-day waits on 2026-11-14 and requested completion
today. This is a new, prospectively registered experiment. It does not
relabel the earlier whole-second observations or claim week-to-week stability.
The existing behavior, identity, parity and security gates remain.

- **Hypothesis:** One safe process-table pass cuts the mean elapsed time to
  at most 400 ms and at most 40% of the lower of two stable six-hour
  pre-change windows, with zero changed fixture actions.
- **Measurement:** Before changing the command, record a single UTC epoch as
  `end`. Run the query below twice with `from_hours` 12 and `to_hours` 6,
  then with `from_hours` 6 and `to_hours` 0. Both windows must start after
  the monotonic timing deployment. Record the result before implementation.
  After deployment, wait 15 minutes and query samples from deployment until
  the end of that 15-minute interval. Run the existing action-parity fixtures
  and hosted CI.
- **Success:** Each baseline window has at least 200 valid tagged samples;
  means differ by at most 20% of the larger. The post-change interval has at
  least 10 valid samples, mean at most 400 ms and at most 40% of the lower
  before mean. Fixture action differences and unintended priority actions
  are zero.
- **Pivot:** Missing or unstable baseline samples make the in-use comparison
  inconclusive. Use a separately registered controlled fixture benchmark;
  do not claim an in-use gain. Missing or unstable post-change evidence also
  stays inconclusive. A changed priority decision, unresolved identity race
  introduced by the candidate, or unknown platform semantics keeps the old
  command. Do not weaken parity to meet the deadline.
- **Anchor:** [migration plan](rust-migration.md),
  [snapshot safety prediction](app-priority-snapshot-prediction.md), Basili,
  Caldiera and Rombach (1994), Goal Question Metric, and Munafò et al.
  (2017), preregistration.

```sh
end=$(date +%s)
jq -c -s --argjson end "$end" --argjson from_hours 12 --argjson to_hours 6 '
  (($end - $from_hours * 3600) | todate) as $a |
  (($end - $to_hours * 3600) | todate) as $b |
  [.[] | select(.task == "app-priority" and .timing_source == "monotonic-ms"
    and .timestamp >= $a and .timestamp < $b) | .duration_ms] |
  {runs: length, mean: (if length > 0 then add / length else null end)}
' ~/.dotfiles-stats.jsonl
# Repeat with from_hours 6 and to_hours 0 using the same end.
```

Use the same query after deployment with explicit deployment and end epochs:
select tagged records with `.timestamp >= ($deployed | todate)` and
`.timestamp < (($deployed + 900) | todate)`. The interval starts after the
new executable is active. Record the deployed source identity and actual
start and end; do not combine old and new code.

## Baseline result and same-day pivot

The baseline was captured after prediction commit `89560f6`, ending at
2026-11-14 14:31:38 UTC. The earlier six-hour window had 343 samples and a
mean of 2,805.31 ms; the later window had 350 samples and a mean of
1,510.40 ms. Both counts passed, but the means differ by 46.16% of the larger.
The preregistered 20% stability floor failed. This is not a usable in-use
baseline and cannot establish an in-use improvement.

Before implementing the fallback benchmark or a candidate, register it here:

- **Hypothesis:** On a fixed synthetic process table, the safe candidate
  preserves every ordered action while its median elapsed time is at most
  40% of the existing command and at most 400 ms.
- **Measurement:** On a fresh hosted macOS runner, run
  `heavy-run --exclusive python3 scripts/app-priority-synthetic-benchmark.py
  --base <base> --candidate <candidate> --pairs 30`. The benchmark uses
  isolated HOME, XDG configuration and PATH, fixed process and ancestry
  responses, and mock priority actions. Alternate order in successive pairs.
  Record all 60 elapsed times and both ordered action logs. No real process
  receives a priority change.
- **Success:** All 30 pairs finish, every ordered action log matches, no real
  priority command executes, median candidate/base is at most 0.40, and the
  candidate median is at most 400 ms. The existing targeted parity checks and
  hosted CI also pass.
- **Pivot:** A mismatched action, missing or failed sample, real process
  action, unsupported matching semantics, identity risk, or ratio above 0.40
  rejects the candidate. Keep the old command and do not claim an in-use
  gain. Fixture results describe only the fixed workload.
- **Anchor:** [snapshot safety prediction](app-priority-snapshot-prediction.md),
  [migration plan](rust-migration.md), Basili et al. (1994), GQM, and
  Munafò et al. (2017), preregistration.

The fixture benchmark accepts only reviewed source trees. Its mock PATH is not
an operating-system sandbox: source that invokes an absolute priority tool
could bypass it. Review both command trees and their selected helpers before
running a pair. The hosted workflow's one same-source pair checks the fixture;
it does not qualify the registered 30-pair decision.

Once both source trees have been reviewed, dispatch the hosted workflow on a
branch that contains it, supplying the full baseline and candidate commit IDs:

```sh
gh workflow run app-priority-fixture.yml --ref <branch> \
  -f baseline_sha=<baseline-commit> -f candidate_sha=<candidate-commit>
```

The hosted job archives the specified commits into its private runner
temporary directory, runs the registered 30 pairs through `heavy-run
--exclusive`, and fails if the action parity or numeric thresholds fail.
It does not establish process selection outside the fixed fixture.

## Same-source negative control

Register this control before dispatch. The earlier single pair only checked
the harness; it did not exercise the 30-pair decision.

- **Hypothesis:** Comparing the same reviewed tree against itself cannot
  satisfy the required 60% reduction. The hosted decision must reject it.
- **Measurement:** Dispatch `app-priority-fixture.yml` with both full commit
  IDs set to `2dba87e9a17774c199dd8ea6abfdb17a3f872616` and retain the
  job result and all 30 pairs. This is an intentional negative control.
- **Success:** Exactly 30 pairs preserve the fixed action log, and the decision
  fails because the ratio is above 0.40 or the candidate median exceeds
  400 ms. Zero priority changes reach real processes.
- **Pivot:** A passed decision, missing pair, action mismatch, execution
  failure or ambiguous job result does not validate the threshold. Stop and
  correct the harness or method before judging a candidate. Do not relabel an
  infrastructure or setup failure as a successful negative control.
- **Anchor:** the same-day fallback above, GQM (Basili et al., 1994), and
  preregistration (Munafò et al., 2017).

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

## Fixture-only batched-selector candidate

Register before implementation. The live `bin/app-priority` is not modified
by this experiment. A candidate will live under `scripts/` and will be copied
into a disposable hosted candidate tree only for the fixed fixture.

- **Hypothesis:** One `pgrep -l -x` query for the fixed default exact names
  can preserve the registered fixture's ordered actions while cutting its
  median runtime to at most 40% of the old command and at most 400 ms.
- **Measurement:** After the same-source negative control validates the
  decision, compare the reviewed baseline and candidate in 30 alternating
  hosted pairs. Extend the existing mock to return the same frozen fake
  processes for the grouped query; do not change the expected actions. Run
  existing hosted checks and fixture tests.
- **Success:** All 30 pairs finish, all expected actions and output match,
  no real process receives a priority change, and both registered timing
  limits pass. The live command and its installer remain unchanged.
- **Pivot:** A mismatch, missing sample, invalid batch output, unsafe mock
  boundary or failed numeric threshold rejects this candidate. Even if the
  fixture passes, earlier process discovery can age a PID before an action.
  Do not deploy until a separately reviewed design preserves identity and
  live selection semantics; unresolved identity keeps the old command.
- **Anchor:** [snapshot prediction](app-priority-snapshot-prediction.md),
  [same-day fallback](app-priority-same-day.md#baseline-result-and-same-day-pivot),
  Basili et al. (1994), GQM, and Munafò et al. (2017), preregistration.

This changes the order of source preparation only. It does not waive the
snapshot prediction's identity or parity requirements for deployment, and a
fixture result is not evidence of behavior on a changing process table.

The fixture candidate rejects malformed rows, duplicate IDs and inconsistent
status/output pairs by falling back to individual queries. This is not an
identity check.

The fixture candidate is `scripts/app-priority-candidate.sh`; the live command
is unchanged. The hosted job copies this file into its disposable candidate
tree only when the `fixture_candidate` input is true. Use the reviewed
candidate commit and include `-f fixture_candidate=true` in the manual
dispatch. Remove the fixture candidate when a safe implementation is deployed
or this approach is abandoned. A passing fixture does not clear the identity
boundary or establish an in-use benefit.

### Duplicate grouped ID control

The first candidate accepts repeated IDs in grouped output. That can repeat
an action, so the candidate now falls back to individual queries.

- **Hypothesis:** The duplicate fixture fails against candidate `b09aeb0`
  and passes with the duplicate guard, with exactly the original action log.
- **Measurement:** Run the hosted fixture tests once with the first candidate
  and the duplicate test, then run them with the corrected candidate. No
  live priority command is used.
- **Success:** The first run reports an action-log mismatch in the duplicate
  case; the corrected run passes all fixture cases with zero extra actions.
- **Pivot:** Any earlier setup or unrelated failure is inconclusive; inspect
  that failure before changing the fixture. A mismatch after the guard keeps
  the candidate in draft.
- **Anchor:** the fixture-only candidate prediction above and the existing
  action-parity gate.

### Fixture workflow queue correction

Three obsolete checks from earlier revisions of this pull request remained
queued after later pushes. The fixture workflow lacked the pull-request
concurrency rule used by the main CI workflow. The obsolete jobs were owned
by this session and were canceled while still queued.

- **Hypothesis:** A pull-request-scoped concurrency group cancels an older
  check for the same pull request, while manual controls are not canceled.
- **Measurement:** Run the focused workflow configuration test before and
  after adding the group, then verify the changed workflow in hosted CI.
- **Success:** The configuration test fails on the missing group and passes
  after the change; the group uses the pull-request number or unique run ID, and
  `cancel-in-progress` is true only for pull-request events.
- **Pivot:** If a manual control can share a cancellation group with another
  manual run, or the configuration cannot be parsed, do not enable automatic
  cancellation. The test verifies configuration, not GitHub scheduling.
- **Anchor:** `.github/workflows/ci.yml` concurrency policy and the three
  observed superseded fixture jobs.

### Hosted Linux preflight

The macOS jobs are queued. Before running any additional fixture, register a
Linux preflight on a GitHub-hosted runner. It uses the same fake processes and
mock priority commands; it does not replace the macOS tests or timing.

- **Hypothesis:** The duplicate-action regression reproduces on hosted Linux
  and the corrected selector preserves the fixed action log there.
- **Measurement:** Run the exact hosted fixture unit tests on the first and
  corrected candidates in separate GitHub-hosted Linux jobs.
- **Success:** The first candidate fails the duplicate-action case; the
  corrected candidate passes all fixture cases with no real priority action.
- **Pivot:** A setup or unrelated failure is inconclusive; inspect its log.
  Linux results do not qualify macOS semantics, timing or process identity.
- **Anchor:** the duplicate grouped ID control above and the hosted fixture.

### Linux comparison preflight

The macOS negative control remains queued. Register a separate Linux
preflight before running it; it checks the comparison path, not Mac speed.

- **Hypothesis:** Thirty same-source mocked pairs on hosted Linux preserve
  the action log and fail the 0.40 speed threshold.
- **Measurement:** Run the fixed benchmark on a GitHub-hosted Linux runner
  with an explicit preflight flag and identical reviewed source commits.
- **Success:** All 30 pairs complete with identical actions, and the ratio
  exceeds 0.40 or the candidate median exceeds 400 ms. No real priority
  action runs.
- **Pivot:** Missing samples, setup errors, action mismatch or an unexpected
  passing result leave the control inconclusive. Linux evidence does not
  replace the registered macOS control, candidate timing, or identity gate.
- **Anchor:** the same-source negative control and hosted Linux preflight above.

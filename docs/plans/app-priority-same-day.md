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

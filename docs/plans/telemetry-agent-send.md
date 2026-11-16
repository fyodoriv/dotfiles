# Telemetry agent send failures, 2026-11-16

The hourly LaunchAgent `com.dotfiles.telemetry` sent nothing from
2026-11-11 to 2026-11-16. `telemetry.log` held only `send failed (http 000)`
entries (9 tries in 5 days) and events were pending. A manual `dotfiles
telemetry send` on 2026-11-16 sent them in 4.7 s.

## Pre-registered

- **Hypothesis**: the daily path gave a late request a limit of 1 to 3 seconds
  (what was left of a 3 second budget), and a busy Mac needs more. With no
  request under 5 seconds and a 30 second budget, failed hourly sends fall from
  9 of 9 logged tries to 0 over the next day.
- **Measurement**: `dotfiles telemetry status` (last send today, pending 0)
  is the primary check. The number is in `docs/metrics.md`: days since the
  last successful send, from `last_send` in the state file. The old row
  counted `send failed` lines in 24 hours; that misfires at a 15 minute
  cadence, where one bad day gives dozens of lines.
- **Success**: `last_send` is today after the apply, and the metric stays at 1
  or less.
- **Pivot**: 2 or more days since the last send, with the new log line shape
  (`curl exit N`): the cause is then the network at those moments, not the
  budget. Read the exit codes, and make the agent wait for the network.
- **Anchor**: Basili, Caldiera and Rombach 1994 (GQM); Nygard 2018, *Release
  It!* (timeouts: a limit must be longer than the normal latency under load).

## Evidence

The agent runs `/bin/bash bin/dotfiles-telemetry daily` (plist, `launchctl
print`), `Nice 15`, spawn type background. The Mac does not sleep (caffeinate
and Amphetamine assertions), so the failures were not a wake with no network.
`curl https://eu.i.posthog.com` takes 0.35 to 0.55 s in the same environment
(`env -i`, `nice -n 15`, `taskpolicy -b`): DNS and TLS are fine.

The old code gave the daily send 3 seconds in total. The gains measurement
(zsh starts) is not counted in it, but the request after it got what was left,
as an integer number of seconds. A run of the agent path with the gains event
due (a scratch copy of the state, a probe in place of curl that makes the same
TLS request and logs its limit and time, load average 17 to 100):

```
rc=0 max=3 ms=382      stats request
rc=0 max=2 ms=373      commands request
rc=0 max=1 ms=408      gains request: a limit of 1 second
whole run ms=3570      over the 3 second budget
```

A request that needs 0.4 s on a quiet Mac gets a limit of 1 s: a 2.5 times
slower answer fails with curl exit 28, and the old code logged only `http 000`
(the exit code was thrown away). This is the likely cause, not a proven one:
the old log kept no exit code, so no logged failure can be matched to it. The
gains measurement is repeated on every try until a send works, so a try that
failed once failed again the same way. The new log line proves or rejects it.

Red CI before the fix: run 43873234863, 13 of the new tests fail on the old
code (the budget, the 5 second floor, the exit code in the log, the 10 minute
retry, the 900 s interval, the long measurement, and the gate cases).

## Change

- A request on the daily path never starts with less than 5 seconds of the
  budget left (the send stops with no failure); the budget is 30 seconds, each
  request may take up to 10.
- The failure line names curl's exit code and its limit:
  `send failed (http 000) curl exit 28 (timed out) limit 10s after 4s`.
- A failed daily try is repeated after 10 minutes (the gate used to wait an
  hour); the agent runs every 15 minutes (it was every hour). Each later
  failure in the same UTC day waits longer: 10 minutes, then an hour, then 6
  hours. An HTTP 4xx waits for the next UTC day. A good send resets the run
  of failures, and there is at most one good send a day. So a lasting failure
  costs at most 4 tries a day, not 96.
- The daily and the first-run gates in `lib/stats.sh` read the org policy file
  (task `telemetry-sink-managed-shell-gates`). They skip the consent question
  only for a top-level `consent: managed` that appears once; a nested key, a
  repeated key, or text that is not one JSON object means "not sure", and the
  question is asked. The send side stays safe either way (`not_now`).

## Results

- Red before the fix: CI run 43873234863, 13 new tests failed on the old code.
- Green after the fix: CI run 43876051767 (the PR's head at that time).
- Stability on a hosted macOS runner (a throwaway draft PR, run
  43876114691, closed unmerged), 20 runs of each case with two copies of
  `telemetry.bats` and `telemetry-sink.bats` looping in the background; the
  first two groups ran at a load average of 25 to 44 (4 cores), the rest at a
  load of 3 to 4 (the background copies had ended their runs):

  | Case | Runs | Passed |
  |---|---|---|
  | `telemetry.bats` a normal command on a terminal asks once (the task `telemetry-terminal-request-count-diagnostic`) | 20 | 20 |
  | `telemetry.bats` request count diagnostic | 20 | 20 |
  | `telemetry-gains.bats` a zsh that fails or takes over 5 seconds (the task `telemetry-gains-timeout-test-load-sensitive`; load as described below) | 20 | 20 |
  | `telemetry-gains.bats` a long measurement leaves the gains request its full limit | 20 | 20 |
  | `telemetry-sink.bats` gates (the task `telemetry-sink-managed-shell-gates`) | 20 | 20 |
  | `telemetry.bats` every daily-path case | 20 | 20 |
  | `telemetry.bats` a failed request logs the curl exit code | 20 | 20 |
  | `telemetry.bats` a hung request | 20 | 20 |

- Task `telemetry-terminal-request-count-diagnostic` is closed because its
  Success shipped in #591 (the receipt that prints the request count). The
  cause of that flaky count is not known, and nothing in the send path
  changed for it. Its two cases passed 20 of 20 in the loop above.
- Task `telemetry-sink-managed-shell-gates` is closed: the gates read the
  policy file, a trace test shows no new process on the no-policy path, and
  20 of 20 runs passed.
- Task `telemetry-gains-timeout-test-load-sensitive`: stays open in `TASKS.md`. Its Success is 20 of 20 while a second full
  Bats run is active. The earlier loop ran at a load of 3 to 4 against 2
  files for most cases, which is not that. A second hosted run (throwaway PR,
  closed) passed 20 of 20, but its background full run ended early: the load
  fell from 50 to 2 by run 8, so about 2 runs were under real load. So the
  criterion is not met as written, and the block says what to rerun.
- Still to measure after the apply: the metric in `docs/metrics.md`.

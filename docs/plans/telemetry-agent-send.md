# Telemetry agent send failures, 2026-11-16

The hourly LaunchAgent `com.dotfiles.telemetry` sent nothing from
2026-11-11 to 2026-11-16. `telemetry.log` held 9 lines `send failed (http 000)`
and 63 events were pending. A manual `dotfiles telemetry send` at 2026-11-16
sent 65 events in 4.7 s.

## Pre-registered

- **Hypothesis**: the daily path gave a late request a limit of 1 to 3 seconds
  (what was left of a 3 second budget), and a busy Mac needs more. With no
  request under 5 seconds and a 30 second budget, failed hourly sends fall from
  9 of 9 logged tries to 0 over the next day.
- **Measurement**: `awk -v s="$(date -u -v-24H +%FT%TZ)" '$1>=s && /send failed/{n++} END{print n+0}' ~/.local/state/dotfiles/telemetry.log`
  (the row in `docs/metrics.md`), and `dotfiles telemetry status` (pending 0,
  last send today).
- **Success**: 0 failed sends in 24 hours after the apply, and `last_send` is
  today.
- **Pivot**: 3 or more `send failed` lines in 24 hours with the new line shape
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
  hour); the agent runs every 15 minutes (it was every hour).
- The daily and the first-run gates in `lib/stats.sh` read the org policy file
  (task `telemetry-sink-managed-shell-gates`).

## Results

Filled in after CI: see the PR.

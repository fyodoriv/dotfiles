# Observability

`app-priority` marks valid monotonic millisecond samples with
`timing_source: monotonic-ms`. If the clock fails, it still records the run
without that marker. Filter on the marker for performance comparisons: older
samples were rounded to whole seconds. The interval excludes the first clock
process startup and the final stats write; assess both clock processes when
measuring total job cost.

The [same-day experiment](plans/app-priority-same-day.md) uses a controlled
process-table fixture when the in-use baseline is unstable. Its benchmark
runs on a GitHub-hosted macOS runner and compares reviewed source trees
with mock priority commands. An explicit hosted Linux preflight checks the
comparison path only. Neither proves an in-use speedup.

How to see what dotfiles did on this Mac, what failed, and how healthy it is.
Everything stays on the Mac, with one exit that needs your yes:
`dotfiles telemetry` (see [Telemetry](#telemetry)). `dotfiles metrics --share` writes an aggregate-only
snapshot only when you ask for one.

## Logs

| Log | Written by | What one entry holds | Read it with |
|---|---|---|---|
| `~/.dotfiles-stats.jsonl` | `lib/stats.sh` `log_run`, and the doctor | One JSON line per automation run: `task`, `timestamp`, `seconds_saved`, `units`, `ok` (true or false), `duration_ms`; doctor runs add `pass`, `fail`, `fixed`, `warn`, `skip` counts. `bin/dotfiles-install run` adds one `install` line per real run, with the heal doctor's `fail` count. An interactive zsh adds one `shell-start` line a day (`duration_ms` from `~/.zshrc` start to the first prompt). No paths or messages. | `dotfiles stats`, `dotfiles doctor --trends`, [metrics.md](metrics.md) |
| `~/.local/state/dotfiles/commands.jsonl` | `bin/dotfiles` through `lib/stats.sh` `log_command` | One JSON line per `dotfiles <command>` run: `command` (the top-level command name from the dispatch list, never an argument), `timestamp`, `ok`, `duration_ms`. Nothing else. | `jq`, [Telemetry](#telemetry) |
| `~/.local/state/dotfiles/errors.jsonl` | `lib/errors-log.sh` `log_error` | One JSON line per failure (see [Errors](#errors)) | `jq` (below) |
| `~/.local/state/dotfiles/load-samples.tsv` | `bin/dotfiles-load-sampler` (every 30 s) | Load, CPU, memory, swap, process count, top 3 process names, and who owns each (PID, parent, redacted 80-char command) | `dotfiles-load-sampler --report 24`, `dotfiles metrics`, the `load` dataset of the tooling health dashboard |
| `~/.local/state/dotfiles/gate-timings.jsonl` | `scripts/gate-timed.sh` (each `make check` step) | `ts`, `step`, `seconds`, `status` | `dotfiles metrics --table`, the speed review in `/tooling-checkup`, the `gate` dataset of the tooling health dashboard |
| `~/.local/state/dotfiles/scorecard.json` | `scripts/benchmark-run.sh` (full runs) | The latest competitive scorecard | `dotfiles metrics --table` |
| `~/.local/share/dotfiles/logs/*.log` | each LaunchAgent | Free-text job output, trimmed by each job | `tail`, `rg` |

The JSON logs are content-free on purpose: counts, fixed codes, and check IDs,
never file contents, paths, or command output. Only the LaunchAgent text logs
hold free text, and they never leave the Mac. The load samples name processes,
so `dotfiles metrics --share` keeps only their numeric lines.

`log_run` allow-lists its fields too: a task is a short lowercase name and
`units` a number; anything else is written as `invalid` and `1`. The outcome
(`log_run <task> [units] [ok|error] [duration_ms]`) becomes `ok` true or false,
and a non-number duration falls back to the script run time (`$SECONDS`).

Tests never write the real errors or stats logs: both logs stay off inside
any bats test unless the test sets `DOTFILES_ERRORS_LOG=1` or
`DOTFILES_STATS_LOG=1`, and the Makefile and `tests/test_helper.bash` also
export both as `0`. `tests/errors-log.bats` fails if any of this goes away.

## Errors

`log_error <story> <source> <code> [check]` appends one line to
`~/.local/state/dotfiles/errors.jsonl`:

```json
{"ts":"2026-10-16T21:10:00Z","story":"US05","source":"doctor","code":"check_failed","check":"git.user_name"}
```

- Every field is allow-listed: `story` is `US01`–`US99`, `source` is
  `doctor`, `sync`, or `morning`, `code` is a short fixed code, and `check` is
  a check ID. Any other value is written as `invalid`, so no free text can
  leak into the log.
- `story` names the user story the failure breaks, so failures map to
  [user stories](user-stories/README.md) and [metrics](metrics.md).
- The log keeps the last 2000 lines. `DOTFILES_ERRORS_LOG=0` turns it off.

| Source | Code | Story | When |
|---|---|---|---|
| `doctor` | `check_failed` (with `check`) | US05 | a check still fails at the end of a run |
| `sync` | `apply_failed`, `fetch_failed`, `pull_failed`, `push_failed` | US05 | the 30-minute sync job could not finish a step |
| `morning` | `pull_failed` | US02 | `morning` could not pull a repo |

Read it:

```bash
jq -s 'group_by(.story) | map({story: .[0].story, failures: length})' ~/.local/state/dotfiles/errors.jsonl
jq -r 'select(.source == "doctor") | .check' ~/.local/state/dotfiles/errors.jsonl | sort | uniq -c | sort -rn | head
```

There is no external error reporter by default. dotfiles is a local tool, and
its privacy contract keeps machine data on the machine (accepted push back,
agentbrew new-project requirements map, 2026-10-16). One opt-in exception: an
org overlay can forward new error log lines to its own log system (see
[Org log sink](#org-log-sink)); never to a public service.

## Telemetry

Asked at install; on only after you say yes (Enter counts as yes).

`bin/dotfiles-telemetry` is the one sender. It can send two content-free
local logs to PostHog EU (`https://eu.i.posthog.com/batch/`): the stats log
and the commands log (see [Logs](#logs)). It also sends two events built
from the install receipt (see [Gain events](#gain-events)). The numbers feed
a performance dashboard (p50 and p95 per command, version, and runtime) and a
regression gate. The dashboard is private to the maintainer, who reads the
totals and averages.

### The question

`bin/dotfiles-install run` asks it on a terminal, right after the
prerequisite check. It cannot be missed: a blank line, a banner ("Help make
dotfiles faster: share anonymous performance numbers?"), what is sent, one
example event as JSON, the privacy promise, where the numbers go, how to change
the answer, then `Share anonymous performance numbers? [Y/n]`.

- **No key, no question.** With no key nothing could be sent, so nobody is
  asked and the installer prints nothing about telemetry. The committed
  `config/telemetry-key` holds the project's write-only key since 2026-11-10;
  a fork that empties it gets no question.

- Enter or `y` records **yes**. `n` records **no**. One line confirms the
  answer and names the command that changes it.
- Keys typed before the question shows are thrown away, so a stray Enter is
  never an answer.
- **A yes covers only later events.** Both cursors move to the end of the
  logs, so nothing recorded before the yes is ever sent. One exception: the
  shell start time before the install and the install day are a baseline,
  measured before the yes. They leave in the `dotfiles.gains` event (see
  [Gain events](#gain-events)), next to the `dotfiles.install` event.
- **No terminal** (an agent, a script, `CI` set): no question. The answer
  stays **unset** and nothing is sent. The first normal `dotfiles` command on
  a terminal asks. It asks only when stdin, stdout, and stderr are a
  terminal, so never in a pipe, a hook, a scheduler, or an agent run. This
  question shows `[y/n]`: only a typed `y` or `n` is an answer, because the
  person did not expect a question there.
- **It does not nag.** It never shows before `help`, `version`, `cd`,
  `actions`, or a command with `--help`, `--json`, or `--quiet`. With no
  answer it comes back at most once a day and 3 times in all; then it stays
  silent until you run `dotfiles telemetry ask`, `on`, or `off`. A run that
  does not ask starts no new process. After a dismissed question the day is
  kept as a file time (`telemetry.asked-until`, set to the next UTC midnight),
  because bash 3.2 has no clock: a run compares it with the time of a bash
  here-string, which is "now". Bash removes that itself, so no extra file
  stays on disk. Only after that midnight, or with a state file from before
  the marker existed, does a run start one `date`.
- An answer is never asked again. A later install never changes a no. An
  explicit opt-out at a later install (see [Turn it off](#turn-it-off))
  records no, also over an earlier yes.
- A Mac that had dotfiles before the question has no answer: it is unset, and
  is asked once. If telemetry was turned off there, the answer is no.

### What is sent

Per log line: the event name (`dotfiles.run` or `dotfiles.command`), its
time, the task or command name, `ok`, `duration_ms`, and the count fields
(`seconds_saved`, `units`, `pass`, `fail`, `fixed`, `warn`, `skip`). Added at
send time: `app_version` (the short SHA of the last upstream commit in the
checkout, so a local commit never makes a per-machine value; a checkout whose
`origin` is not the upstream repo sends `unknown`), `os` (`darwin`
or `linux`),
`arch`, and `runtime` (`shell`). All keyed by a random install id.

```json
{
  "event": "dotfiles.command",
  "distinct_id": "0f3c9a1e5b7d4c2a8e6f1b3d5a7c9e0f",
  "properties": {
    "$process_person_profile": false,
    "$geoip_disable": true,
    "app_version": "f6006d0",
    "os": "darwin",
    "arch": "arm64",
    "runtime": "shell",
    "command": "doctor",
    "duration_ms": 1840,
    "ok": true
  },
  "timestamp": "2026-11-09T18:04:11Z"
}
```

### What is never sent

A path, file name, host name, user name, argument, message, or content. No
person profile (`$process_person_profile: false`). No replay, flags, or
surveys.

**Your IP address.** PostHog receives the request IP address, like any web
server. GeoIP lookup is disabled (`$geoip_disable: true`) and no location is
stored.

How the code enforces it:

- The sender builds each event from an allowlist. A field that is not on the
  list is dropped. A task name must be on the fixed list `TASK_NAMES` in the
  sender, and a command name on the fixed list `COMMAND_NAMES` there (the
  upstream dispatch arms; a fork's own command name is never sent); any
  other word sends no name. A number field must be a number; a time must be
  a UTC timestamp; the version must be a git short SHA.
- The commands log gets only names from the dispatch list of `bin/dotfiles`.
  A mistyped command is not recorded.
- `tests/telemetry.bats` seeds the logs with a home path, a user name, a
  plain lowercase word, a plain uppercase word, an email, a URL, and a long
  token, and fails if any reaches the request body.
- `tests/telemetry-gains.bats` does the same for the install receipt: a path
  where a number belongs, a profile name that is not on the list, and a time
  that is not a UTC timestamp never reach the request body.

### Gain events

These events show how much dotfiles helps against the same Mac before the
install, and against the same Mac with a default shell. The install receipt
(`~/.local/state/dotfiles/install-receipt.json`, written by
`bin/dotfiles-install run`; see `lib/mac-baseline.sh`) holds the numbers from
before the install. With no receipt the install event is not sent, and the
gains event carries only the three numbers measured in the send. A receipt that is
too large, is not JSON, or has no real before time counts as no receipt for
the gains event.

| Event | When | Properties (plus the common ones) |
|---|---|---|
| `dotfiles.install` | Once per receipt. A new install run writes a new end time, and that sends a new event. Never for an install that finished more than 30 days ago (the age cap of the logs) or in the future. | `seconds` (time to configured, measured), `ok`, `profile` (`core` or `full`; any other value is dropped). The event time is the end of the install. |
| `dotfiles.gains` | At most once a day, with the daily send. | `zsh_ms_before` (receipt `.before.zsh_ms`, measured), `zsh_ms_now` (measured), `zsh_min_ms_now` and `zsh_min_ms_stock` (measured: the fastest of 7 runs, now and with an empty zsh config), `days_since_install` (days since receipt `.before.taken_at`). With no receipt: `zsh_ms_now`, `zsh_min_ms_now` and `zsh_min_ms_stock` only. With no number at all: no event. |

- `dotfiles.run` carries `seconds_saved` as a whole number. It is an
  estimate: runs times the per-task table in `lib/stats.sh`
  (`_task_estimate`).
- **Two pairs of shell numbers.** All are the full run time of
  `zsh -i -c 'exit 0'` (`baseline_zsh_ms` in `lib/mac-baseline.sh`).
  `zsh_ms_before` and `zsh_ms_now` are the median of 3 runs, as in the
  receipt. `zsh_min_ms_now` and `zsh_min_ms_stock` are the fastest of 7
  runs. Compare a number only inside its pair.
- **Why the fastest run.** Other work on the Mac only adds time to a run.
  Measured on 2026-11-10: 9 medians of 3 at a load of 20 to 30 ran from 13
  to 54 ms for the stock shell. 9 minimums of 7 at a load of 12 ran from 12
  to 14 ms (stock, spread 15%) and from 136 to 159 ms (now, spread 16%).
  A very busy Mac still raises the fastest run: one send taken while a test
  suite ran measured 234 ms (now) and 23 ms (stock). So the dashboard tile
  takes, for each install, the lowest value of its last 14 days.
- **The default-Mac baseline.** `zsh_min_ms_stock` is the shell start of the
  same Mac with an empty zsh config. zsh gets a new empty temp folder as
  `ZDOTDIR`, so it reads no user file. The folder is removed afterwards,
  also when the run is stopped. `/etc/zshrc` still loads, as on a default
  Mac. dotfiles adds shell features, so `zsh_min_ms_now` can be higher than
  `zsh_min_ms_stock`. The number shows that cost honestly.
- **When the three send-time numbers are measured.** In the send that
  builds the gains event: at most once a day, in the background daily send
  or a manual `dotfiles telemetry send`. A normal command never measures.
  `dotfiles telemetry status` never measures. A `send --dry-run` measures
  each once when a gains event is due. Each measurement has its own limit of
  5 seconds, so a gains event adds at most 15 seconds. When one fails or
  takes longer, it is stopped. A fastest-of-7 number then uses the runs that
  finished; with none, that field is left out. The send goes on.
  This time does not count against the 3-second limit of the daily send.
- **No number, no event.** With no receipt and no measurement there is no
  gains event. The gains day is still set, so the measurements are tried at
  most once a day. The pending count of `status` counts a gains event that
  is due before it is known whether a number can be measured.
- **Consent.** The install event is sent only when the install finished at or
  after the exact time of the yes. The state file keeps that time as
  `consent_time`, next to the day (`consent_at`). The time stays on the Mac
  and is never sent. A state file from before `consent_time` existed has the
  day only, so for that file the install must have finished on or after the
  day of the yes. `zsh_ms_before` and `days_since_install` are a
  baseline from before the yes. This is the one exception to "a yes covers
  only later events", and the consent text says so. `zsh_min_ms_now` and `zsh_min_ms_stock` are not
  part of that exception: they are measured at send time, after the yes.
- **Older yes answers.** Both events need a yes given on or after
  `2026-11-10` (`GAINS_SINCE` in the sender), the day they shipped. A person
  who said yes before that day agreed to a text without the baseline
  exception, so that yes does not cover them. `dotfiles telemetry on` gives
  a new yes: it shows the text again and records today as the day, and now as
  the time.
- **Switches.** Without a stored yes, or with `CI`, `DO_NOT_TRACK`, or
  `DOTFILES_TELEMETRY=0` set, the events are not built at all: not in a
  send, not in a dry run, and not in the pending count.
- **Checks.** A receipt number must be a number from 0 to 999,999,999 and
  leaves as a whole number (a negative zero leaves as 0). `ok` must be a
  boolean. A time must be a real UTC time; a day such as month 13 drops only
  the event that needs it. Any other value is dropped. A receipt over 64 KB
  is not read.
- **Cursors.** The state file keeps `install_sent` (the end time of the last
  install that was sent) and `gains_day`. Each moves only after the endpoint
  answers 2xx for a request that held its event. One exception: when a gains
  event was due and no number could be measured, the gains day is still set.
- The local view is `dotfiles metrics --gains`. It prints the default shell
  start next to before and now. With no receipt it prints now and the
  default shell start. It sends nothing.

### Product tiles on the dashboard

The private dashboard has one tile for each product question. Each tile is a
HogQL query over the anonymous events. Tool names come from the event name
(`dotfiles.*` or `agentbrew.*`).

| Tile | Question | Kind |
|---|---|---|
| Active installs per week | How many installs sent an event each week? | counted |
| New installs per week | How many installs sent their first event each week? | counted |
| Week-1 retention | Which share of installs is seen again in days 7 to 13? | counted |
| Time to configured and success rate | Per `profile`: median and p95 of `seconds` on `dotfiles.install`, and the share of installs with `ok` true | measured |
| agentbrew time to a clean status, first installs | Median and p95 of `duration_ms` on `agentbrew.install` where `ok` is true, and the share of first installs with `ok` true | measured |
| Saved minutes, last 30 days | Sum of `seconds_saved`, in total and per install | estimated |
| Shell start: default Mac, before, and now | Median over installs of `zsh_min_ms_stock` and `zsh_min_ms_now` (the default-Mac pair; per install the lowest value of the last 14 days), and of `zsh_ms_before` and `zsh_ms_now` (latest `dotfiles.gains` per install) | measured |

Known gaps on 2026-11-10: the retention tile is empty until an install is 14
days old. The time-to-configured tile and the before column of the shell tile are empty
until a Mac with an install receipt sends its events. The default-Mac pair
needs no receipt, so every install fills it. The agentbrew install tile is empty
until a first real agentbrew install whose user said yes to telemetry; a
re-run of its installer sends no install event.

### Org log sink

An org overlay can send the same events to a company log system instead of
PostHog. The overlay drops one settings file. The base repo holds only this
generic setting. With no file, nothing changes: the request is the same as
before.

**Not tested against a real Splunk server.** The tests use a fake receiver
and follow Splunk's public HTTP Event Collector (HEC) format.

The file is `~/.config/dotfiles/telemetry-sink.json`. It must not be writable
by group or others. Example:

```json
{
  "version": 1,
  "kind": "splunk-hec",
  "consent": "managed",
  "error_logs": true,
  "url": "https://splunk.example.com:8088/services/collector/event",
  "token": { "keychain": { "service": "org-telemetry", "account": "hec_token" } },
  "index": "devtools",
  "sourcetype": "dotfiles:telemetry",
  "source": "dotfiles"
}
```

| Field | Meaning |
|---|---|
| `version` | Must be `1`. |
| `kind` | `posthog` (the public default), `splunk-hec`, `file`, or `off`. |
| `consent` | `ask` (default) or `managed`. `managed` needs `splunk-hec` or `file`. |
| `error_logs` | `true` forwards error log lines (see below). Default `false`. Needs `splunk-hec` or `file`. |
| `url` | `splunk-hec` only, required. `https`, no user info in it. |
| `token` | `splunk-hec` only, required. Exactly one of `{"keychain":{"service","account"}}`, `{"file":"~/path"}`, `{"env":"NAME"}`. 1 to 512 characters, no space or control character. A token file must be a regular file that group and others cannot read. |
| `index`, `sourcetype`, `source` | Optional. Each matches `^[A-Za-z0-9_:.-]{1,64}$`. Defaults: sourcetype `dotfiles:telemetry`, source `dotfiles`, no index. |
| `path` | `file` only, required. Absolute or `~/`-relative, inside your home folder, no `..`, and neither the file nor a folder on the way is a symlink. |

An unknown key, a missing field, a bad value, invalid JSON, or a file that
group or others can write makes the policy **invalid**. Then nothing is sent
anywhere (not to PostHog either), no question is asked, and
`dotfiles telemetry status` says `off (sink policy invalid: <reason code>)`.
It never prints the file content. `kind: off` sends nothing and asks
nothing; status says `off by org policy`.

**`splunk-hec`.** One POST to `url` with `Authorization: Splunk <token>` and
`content-type: application/json`. The body is one JSON object per event,
joined by newlines (the HEC batch format):

```json
{"time":1794402251,"source":"dotfiles","sourcetype":"dotfiles:telemetry","index":"devtools","event":{"event":"dotfiles.command","install_id":"0f3c9a1e5b7d4c2a8e6f1b3d5a7c9e0f","app_version":"f6006d0","os":"darwin","arch":"arm64","runtime":"shell","command":"doctor","duration_ms":1840,"ok":true}}
```

The event carries the same event name and properties as the PostHog body (the
same fixed lists), without the PostHog-only `$` flags, plus the install id.
A 2xx answer is success. The PostHog key is never read on this path, and no
request goes to the public default.

**`file`.** One JSON line per event is appended to `path`: the same `event`
object, plus `time` as an ISO string and `sourcetype`. The folder gets mode
700 and the file mode 600. A file over 10 MB is renamed to `<path>.1`
(replacing an old one) and a new file starts. No network request.

**Consent.** With `consent: ask` the stored answer decides, as before, and
the question names the destination ("to your organization's log system at
splunk.example.com") instead of the public dashboard. With
`consent: managed` the tool sends with no stored answer and never asks;
status says `managed by org policy`. A stored no (`dotfiles telemetry off`)
still stops it, and `dotfiles telemetry on` clears that no. The
`dotfiles.install` and `dotfiles.gains` events still need a real stored yes.
`DO_NOT_TRACK`, `CI`, and `DOTFILES_TELEMETRY=0` stop every sink, managed
too.

**Sink change.** The state file keeps a fingerprint of the sink (kind plus
URL host or file path, never the token). When it differs from the stored one
(the first sight of a policy, a changed policy, a removed one), the send
cursors move to the end of the logs first. Events recorded under one
destination never go to another. Every run of `dotfiles-telemetry` except
`status`, `example`, and `send --dry-run` notes the change, also when the
policy says `off` or is invalid (an invalid policy has the fingerprint
`invalid`). So events recorded while the policy said `off` are not sent after
the file is removed. `dotfiles apply` is such a run. One limit: a policy that
was added and removed with no run in between leaves no trace.

**Error logs** (`error_logs: true`, org sinks only). New lines of two local
files that dotfiles itself writes are forwarded, one event per line, named
`dotfiles.error_log`, with sourcetype `dotfiles:error_log` and the fields
`file` and `line`:

| `file` | Path |
|---|---|
| `telemetry.log` | `~/.local/state/dotfiles/telemetry.log` (the sender's own failure lines) |
| `errors.jsonl` | `~/.local/state/dotfiles/errors.jsonl` (the [errors log](#errors)) |

Before a line leaves, URL credentials and anything the repo's secret
patterns cover (`lib/secret-scan.sh`) are replaced by `REDACTED`, your home
path becomes `~`, and a line is cut at 2000 characters. One send takes at
most 200 lines. A cursor per file lives in the state file; a file that shrank
(the tool trimmed it) restarts at its top, and a file seen for the first time
(or after a sink change) starts at its end, so old history never leaves. With
`kind: posthog` or no policy this path does not run: error lines never go to
the public default.

**Token safety.** The token never appears in `status`, `--dry-run` (it shows
`<token>`), the log, an error line, or a process argument list: curl reads the
header from a config on a file descriptor. Status shows the token source
kind only (`keychain`, `file`, or `env`). The Keychain read is
`security find-generic-password -s <service> -a <account> -w`.

**The apply and scheduled path.** With `consent: managed` the
`com.dotfiles.telemetry` LaunchAgent is installed and sends (unless a stored
no); with `kind: off` or an invalid policy it is not installed. The agent does
not see your shell env, so the policy is read from the file
(`dotfiles-telemetry agent-wanted`, used by `dotfiles apply`). For now a
managed Mac with no stored answer sends from this hourly agent only: the
shell-side daily send still looks at the stored yes (task
`telemetry-sink-managed-shell-gates`).

**Check it.** `dotfiles telemetry status` shows the sink (kind and host, or
the file path with `~`), the consent source, error logs on or off, and the
token source. `dotfiles telemetry send --dry-run` prints the exact request
(URL, `Authorization: Splunk <token>`, body) and sends nothing.

### Turn it off

- `dotfiles telemetry off` records no. `dotfiles telemetry on` records yes
  and prints the example and the promise again.
- At install, each of these records no and prints one line that says so:
  `bin/dotfiles-install run --yes --no-telemetry`, `DOTFILES_TELEMETRY=0`,
  `DO_NOT_TRACK=1`.
- At run time, `DO_NOT_TRACK` (any value except empty or `0`),
  `DOTFILES_TELEMETRY=0`, and `CI` stop every send, whatever the stored
  answer is.

The two local logs are still written when telemetry is off. They never leave
the Mac. `DOTFILES_STATS_LOG=0` turns the logs off too.

### Inspect it

- `dotfiles telemetry status`: on or off and why, your answer and its day,
  the key source (`env`, `keychain`, `default`, or `none`; never the value),
  pending events (log lines, and the install and gains events that are due),
  the last send, and the last problem.
- `dotfiles telemetry send --dry-run`: the exact request body of each log and
  of the install and gains events, with the key shown as `<posthog_key>`. It
  sends nothing and changes nothing.

### The key

The project key is write-only: it can add events and cannot read them. Lookup
order: `DOTFILES_POSTHOG_KEY`, then the committed one-line file
`config/telemetry-key`, then the macOS Keychain item (service `dotfiles`,
account `posthog_key`). The committed file is the project's key for everyone.
The env variable is the override: a fork or a test sets it to send to its own
PostHog project. The Keychain item is the owner's key from before the file
existed. The Keychain is read only when the first two hold no
key, and with no key at all the daily path looks at most once an hour. A
value that is not `phc_` plus letters and digits is no key. No key means
nothing is sent. The key is never printed or logged.

### Reliability

- A send never fails a command. Every error is swallowed and one content-free
  line goes to `~/.local/state/dotfiles/telemetry.log` (at most 200 lines).
  The commands log keeps its newest 10,000 lines once it passes 20,000. The
  cut moves the send cursor back by the number of dropped lines, under the
  state lock, so a line that was not sent yet is still sent. The cut drops
  the counted lines only, so a line that a command appends during the cut is
  kept and sent once. While a send runs, the log is left alone until a later
  run. With no state file (nobody answered the question) there is no cursor,
  so `lib/stats.sh` cuts the log by itself with `tail` and `mv`. That path
  needs no jq and works for root, and the log keeps its owner and mode. With
  a state file and no jq the log is not cut until jq is back. A state file
  that you cannot read is treated like no state file: `lib/stats.sh` cuts the
  log by itself, because `cap-commands` could not read the cursor.
- **Never as root.** With `sudo`, the state file, the lock, and the plist
  would become root-owned, and your own runs could not read them afterwards.
  So as root nothing is saved, loaded, or sent, and one line says so. A
  `sudo dotfiles …` run starts no question and no send. An install opt-out
  as root (`--no-telemetry`, `DOTFILES_TELEMETRY=0`, `DO_NOT_TRACK`) cannot
  be saved either: one line says so and names the fix, `dotfiles telemetry
  off` as your user.
- The daily send happens at most once a day. It stops after 3 seconds in
  total; what is left goes on a later run. A request that hangs is killed.
  After a try it waits one hour. A manual `dotfiles telemetry send` allows
  10 seconds per request.
- Every way out of the daily path marks the clock hour in the state file, so
  for the rest of that hour a `dotfiles` run starts no process for the send.
  With `DO_NOT_TRACK`, `CI`, or `DOTFILES_TELEMETRY=0` set, a run never
  starts one.
- **Who starts it.** The LaunchAgent `com.dotfiles.telemetry` (every hour and
  at load; the script sends at most once a day). Also a `dotfiles` run on a
  terminal, as a fully detached child (its own process group, SIGHUP ignored,
  no open terminal), so it lives on when the run ends. A scheduled job never
  starts a send: launchd kills what a job leaves behind when it exits, and
  that could stop a send half way.
- **The LaunchAgent exists only while your answer is yes.** A yes (at the
  question or with `dotfiles telemetry on`) renders its plist and loads it.
  `dotfiles telemetry off` unloads it and removes the plist. `dotfiles apply`
  installs it only when the state file says yes, and removes an installed
  copy otherwise. `dotfiles uninstall` removes it with the other agents. A
  wake never creates a state file or an install id for someone who never
  answered.
- A repeat `dotfiles telemetry on` leaves a loaded job with an unchanged
  plist alone. When a reload is needed and launchd refuses the first load
  (it can, right after an unload), the load is tried once more.
- The apply script for LaunchAgents has the answer (yes or not yes) in its
  change hash. So when the answer changes outside `on` and `off` (a restored
  or hand-edited state file), the next `dotfiles apply` installs or removes
  the agent.
- **A state file that cannot be read.** An old `sudo` run can leave the
  state file root-owned. `dotfiles apply` then reads the answer as "not yes"
  and goes on: it never fails on that file, and the agent stays off. The
  doctor check `chezmoi.telemetry_state_readable` reports a state file that
  another user owns or that you cannot read or write, and prints the fix
  (`sudo chown` and `chmod 600`). It also fails when the state folder itself
  cannot be entered (for example mode 000): the file then looks absent, but
  telemetry can read and write nothing. The fix is `chmod 700` on the folder
  (with `sudo chown` first when another user owns it).
- **Custom state folder.** The job gets `XDG_STATE_HOME` only when that
  variable is set where its plist is rendered (`dotfiles telemetry on` or
  `dotfiles apply`). Set it in the shell that runs them. A background apply
  with no such variable renders the plist without it and looks for the
  answer in `~/.local/state`. The path is XML-escaped in the plist, so a
  folder name with `&` or `<` is safe.
- Each state write takes a short lock, reads the file again, and changes
  only its own fields. The send path never writes the answer. A
  `dotfiles telemetry off` during a send is kept, and the send stops before
  the next request. A writer that stalls for more than 3 seconds loses the
  lock; when it wakes up it reads the file again before it writes.
- The key is never an argument of a process: jq gets it through its
  environment and curl on stdin.
- A first send is small. One send takes at most the newest 2,000 events of
  the last 30 days per log, 500 per request. Older events are skipped for
  good.
- The cursor moves only after the endpoint answers 2xx.
- Recording a command costs a few milliseconds and never throws.
- **State**: `~/.local/state/dotfiles/telemetry.json` (install id, answer and
  its day, two log cursors, the install event cursor, the last gains day,
  last send day, last try; mode 600, written with a temp
  file and a rename). A file whose content is not valid means unset, never
  yes, and the cursors start at the end of the logs. When `jq` itself fails,
  the file is left as it is and nothing is sent, so a stored no is never
  lost. Only an answer or a question creates the file; `status` and the
  hourly wake never do. A log that was cut moves the
  cursor to its end, not to zero. With an org policy the file also keeps the
  sink fingerprint (`sink`) and the error log cursors (`err_cursors`); see
  [Org log sink](#org-log-sink). Delete the file to reset.

## Performance gate

`make perf-gate` (also a step of `make check`) stops a PR that makes a tracked
command slower. `scripts/perf-gate.sh` times each command in
`config/perf-budget.tsv` in two trees in the same run: your working tree and a
checkout of the merge-base with the default branch. It needs no stored
baseline, so it works the same on every machine.

When the working tree has ignored executable links in `bin/`, the gate puts
the same absolute external links in a disposable base clone. It keeps its
shared base cache clean. It rejects unsupported files, relative links, links
into the working tree, conflicting base paths and links that change during a
run. It checks executable content before and after timing; this detects a
persistent change, not every possible change to an external dependency.

- **Fails when** two rules agree that a command is slower, or when it is
  above its ceiling in the budget file. Rule 1: the fastest run in your tree
  is more than 10% and more than 3 ms slower than the fastest run at the
  base. Rule 2: the median of the paired differences (your tree minus the
  base, pass by pass) is over the same limit. Load noise moves one rule; a
  real slowdown moves both. When only rule 1 fires, the gate passes and
  prints `load noise, not a slowdown`.
- **Ceiling at the base**: when the command is over its ceiling at the base
  too, your tree did not cause it. The verdict is `over-ceiling-at-base`, the
  gate prints a note, and it does not fail. The 10% rule still applies to
  that command. An allow line does not lift the ceiling: a command that is
  slower by both rules and over its ceiling fails, with or without an allow
  line. A limit of this verdict: on a machine where the base is always over
  the ceiling, the ceiling does not stop drift under 10% per PR. Lower the
  load, or set a ceiling that fits the machine.
- **How it times**: 2 warmups, then 15 runs per tree, base and head in turn,
  with an empty environment and a scratch HOME. A command that looks slower
  by both rules is timed again, up to two more rounds.
- **Skips** when the diff touches no runtime path: `perf gate: skipped (no
  runtime change)`. The path list is the `PERF_GATE_PATH` lines of the budget
  file at the base and in your tree together, so a PR cannot shrink its own
  scope. `scripts/perf-gate.sh --force` times anyway.
- **Exit codes**: `scripts/perf-gate.sh` exits 0 on a pass or a skip, 1 on a
  slowdown (or a stale allow line), and 2 on a setup error. `make perf-gate`
  and `make check` exit 2 for every failure: that is make's own code for a
  failed step. So a caller of `make` reads "non-zero", and reads the printed
  lines for the reason.
- **Setup errors exit 2, never pass**: no base commit (run `git fetch origin`,
  or set `PERF_GATE_BASE=<ref>`; `PERF_GATE_NO_BASE=1` checks the ceilings
  only), a command that fails in your tree or in the base checkout, a git
  failure, a budget file with no path line or no command, an allow line that
  names no command, a bad `PERF_GATE_RUNS`, an unknown argument, no perl, a
  cache folder that is not an absolute path or cannot be written, a folder
  at the base checkout path that the gate did not build. The gate
  prints the base ref and the date of its last commit, so a stale ref shows.
- **A change to the gate itself**: a PR that changes `scripts/perf-gate.sh`,
  `scripts/perf-gate.pl`, or `tests/perf-gate.bats` changes its own judge.
  The gate prints a warning and exits 2 unless the budget file has a new line
  `PERF_GATE_ALLOW=perf-gate:<reason>`. Review such a PR by hand.
- **Allow lines**: an allow line counts when the base budget file does not
  have the same line (same name and same reason); a line that the base has
  unchanged is stale. On a stale line the gate stops before any timing, exits
  1, and prints `remove this line from config/perf-budget.tsv: <line>`. A PR
  that needs the allow again writes the line with its own reason.
- **Queue**: timing runs through `heavy-run --exclusive` and prints a line
  while it waits for the slot. Inside a heavy-run slot (`heavy-run make
  check`) it runs directly.
- **On a failure**: make the command faster. If the cost is intended, raise
  the ceiling and give the reason in the PR. A step above 10% in one PR also
  needs a `PERF_GATE_ALLOW=<name>:<reason>` line in the budget file; the next
  PR removes it or gives its own reason.
- **New hot-path command**: add its row to the budget file in the same PR.
  A new name whose file the base commit does not have gets the ceiling check
  only. A name that the base budget file has is never new: the base runs its
  own row, so a PR cannot avoid the comparison by pointing the row at another
  file or a wrapper. A row removed from the budget file fails the gate unless
  an allow line names it.
- **Machine output**: `scripts/perf-gate.sh --json` prints `base_min`,
  `head_min`, `ratio`, `paired_delta_ms`, `verdict`, and
  `over_ceiling_at_base` per command, and `estimator`, `problems`, and the
  `over_ceiling_at_base` count at the top. A stale allow line gives
  `{"skipped":false,"ok":false,"problems":[…]}` and exit 1.
- **Base checkouts**: detached worktrees under
  `~/.cache/dotfiles/perf-gate.noindex/<commit>`; the newest two are kept.
  Before each use the gate checks that a checkout is at its commit and has no
  changed, new, or ignored file; if not, it builds the checkout again. It
  builds and removes checkouts under a lock, and removes only its own: a
  folder with the marker `<commit>.ready` next to it. It unlinks a symlink
  without following it. A checkout from before the marker existed has none:
  the prune removes it when it is over 7 days old and git lists it as a
  worktree of this repo, detached at the commit in its name, with a clean
  tree. Any other unmarked folder stays (a worktree on a branch, at another
  commit, or with a changed file can hold your work), and the gate prints a note
  with its path.
- **Field numbers**: the gate measures one machine before a merge. Numbers
  from real installs go to the telemetry dashboard. That dashboard is private
  to the maintainer.

## Health check

`dotfiles doctor` is the health check. It runs every module's checks and
prints one line per check. Every failing line ends with its fix:

```text
  ✗ pull.rebase = true — fix: dotfiles doctor --fix --module git
  ✗ /Users/you/.gitconfig → dotfiles (not managed) — fix: chezmoi apply '/Users/you/.gitconfig'
  ✗ git user.name is set — fix: no auto-fix; follow docs/module-reference.md (git)
```

- `dotfiles doctor --fix` applies every automatic fix; `--module NAME` limits
  the run; `--json` gives each check's status and fix command for scripts.
- The `com.dotfiles.dotfiles-doctor` LaunchAgent runs it weekly with `--fix`.
- The install ends with it (README quick start), so a new Mac starts with a
  health report.
- `tests/errors-log.bats` fails when a `fail` line in `bin/dotfiles-doctor`
  has no fix.

# Observability

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

There is no external error reporter. dotfiles is a local tool, and its
privacy contract keeps machine data on the machine (accepted push back,
agentbrew new-project requirements map, 2026-10-16).

## Telemetry

Asked at install; on only after you say yes (Enter counts as yes).

`bin/dotfiles-telemetry` is the one sender. It can send two content-free
local logs to PostHog EU (`https://eu.i.posthog.com/batch/`): the stats log
and the commands log (see [Logs](#logs)). The numbers feed a public
performance dashboard (p50 and p95 per command, version, and runtime) and a
regression gate.

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
  logs, so nothing recorded before the yes is ever sent.
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
  because bash 3.2 has no clock: a run compares it with a file it writes at
  that moment, in plain bash. Only after that midnight, or with a state file
  from before the marker existed, does a run start one `date`.
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
  pending events, the last send, and the last problem.
- `dotfiles telemetry send --dry-run`: the exact request body, with the key
  shown as `<posthog_key>`. It sends nothing and changes nothing.

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
  state lock, so a line that was not sent yet is still sent. While a send
  runs, the log is left alone until a later run.
- **Never as root.** With `sudo`, the state file, the lock, and the plist
  would become root-owned, and your own runs could not read them afterwards.
  So as root nothing is saved, loaded, or sent, and one line says so. A
  `sudo dotfiles …` run starts no question and no send.
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
- **Custom state folder.** The job gets `XDG_STATE_HOME` only when that
  variable is set where its plist is rendered (`dotfiles telemetry on` or
  `dotfiles apply`). Set it in the shell that runs them. A background apply
  with no such variable renders the plist without it and looks for the
  answer in `~/.local/state`.
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
  its day, two cursors, last send day, last try; mode 600, written with a temp
  file and a rename). A file whose content is not valid means unset, never
  yes, and the cursors start at the end of the logs. When `jq` itself fails,
  the file is left as it is and nothing is sent, so a stored no is never
  lost. Only an answer or a question creates the file; `status` and the
  hourly wake never do. A log that was cut moves the
  cursor to its end, not to zero. Delete the file to reset.

## Performance gate

`make perf-gate` (also a step of `make check`) stops a PR that makes a tracked
command slower. `scripts/perf-gate.sh` times each command in
`config/perf-budget.tsv` in two trees in the same run: your working tree and a
checkout of the merge-base with the default branch. It needs no stored
baseline, so it works the same on every machine.

- **Fails when** the fastest run in your tree is more than 10% and more than
  3 ms slower than the fastest run at the base, or above the command's ceiling
  in the budget file.
- **How it times**: 2 warmups, then 15 runs per tree, base and head in turn,
  with an empty environment and a scratch HOME. It compares the minimums. A
  command that looks slower is timed again, up to two more rounds.
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
  `head_min`, `ratio`, and `verdict` per command.
- **Base checkouts**: detached worktrees under
  `~/.cache/dotfiles/perf-gate.noindex/<commit>`; the newest two are kept.
  Before each use the gate checks that a checkout is at its commit and has no
  changed, new, or ignored file; if not, it builds the checkout again. It
  builds and removes checkouts under a lock, and removes only its own: a
  folder with the marker `<commit>.ready` next to it. It unlinks a symlink
  without following it.
- **Field numbers**: the gate measures one machine before a merge. Numbers
  from real installs will be on the performance dashboard (link: to be added
  with the telemetry timing events).

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

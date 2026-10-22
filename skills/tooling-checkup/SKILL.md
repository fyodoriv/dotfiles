---
name: tooling-checkup
description: >
  One-command health pass for the tooling repositories and the whole Mac. Ships
  outstanding tooling work, refreshes the tooling checkouts and agent config,
  upgrades Homebrew, npm, uv, pipx, mise, and Claude Code, runs `claude doctor`,
  audits LaunchAgents and heavy processes, reads recent machine and tooling
  metrics (load, memory, swap, disk, upgrade failures, Claude Code lag signals),
  reviews where agent tool time went, lints skills, rules, and AGENTS.md files
  against best practices, and researches new ways to work with AI. Then it
  reports what changed since the last run, asks the owner a questionnaire, and
  applies the answers. Use when the user runs "/tooling-checkup", or asks to
  update all tooling and the machine, to tidy up background processes, or to
  check that agent config follows best practices. Don't use for a refresh
  without package upgrades (use update-tooling) or for one task in one
  repository (use ship-it).
disable-model-invocation: true
---

# Tooling checkup

The user runs this by hand every 2 or 3 days. It must be safe to repeat, and
fast when nothing changed. Run twelve phases in order. Each phase ends with a
**Done when** check. Phases 10, 11, and 12 always run, even when an earlier
phase is blocked.

`<skill-dir>` below means this skill's base directory.
`TOOLING_ROOT` defaults to `~/apps/tooling`.

**Scope.** `/tooling-checkup` alone runs all twelve phases. A request for one part
runs Phase 1, that part, and Phases 10 to 12:

| The user asks to… | Run |
|---|---|
| ship what is pending in tooling | Phase 2 |
| update tooling and the machine | Phases 3 and 4 |
| clean up background processes | Phase 5 |
| check machine metrics, or make Claude Code typing faster | Phase 6 |
| check skills and rules against best practices | Phase 7 |
| audit the new-project requirements now | Phase 7, monthly step (pass `--days 0` to `audit-due.sh`) |
| find what makes agents slow | Phase 8 |
| research new ways to work with AI | Phase 9 |

## Hard rules

1. **Tooling repositories only.** Inventory and ship only primary checkouts
   directly under `$TOOLING_ROOT`. Leave every other repository on the machine
   alone, even when you see work there.
2. **Dependabot is not outstanding work.** Do not merge, rebase, or fix a
   dependabot pull request unless the user names it. The exception: an open
   **critical** dependabot alert. Report high alerts as one summary line.
3. **Automation branches are not outstanding work.** The inventory script
   groups them as `bot`. Report the count only.
4. **Never lose work.** No `reset --hard`, `clean`, `checkout .`, `stash drop`,
   plain `--force`, or `git pull --rebase` on a checkout you did not create.
   Never delete a worktree with uncommitted files. Never delete a plist; move it.
5. **Source, not output.** Generated agent config (`~/.claude/`,
   installed skills) and installed LaunchAgents of tooling repos change only
   through their source repo, then `agentbrew sync` or `dotfiles apply`.
6. **Minsky never starts on its own.** Do not start it. Keep
   `~/.minsky/autostart-enabled` absent. Leave `.worktrees/` that an
   orchestrator owns alone.
7. **Public writes.** `/ship-it` delivery in the approved tooling family is
   pre-approved. Every other post, comment, or push outside `$TOOLING_ROOT`
   needs the user's approval for that exact action.
8. **Upgrades are approved.** Running this skill is the explicit request to
   upgrade third-party software. That lifts the `update-tooling` package
   upgrade ban for this run only. macOS updates stay report-only.
9. **Evidence for every claim.** Each "updated", "fixed", "removed", or
   "faster" cites a command run in this session and its result.
10. **Plain English.** Short sentences. One idea per bullet. Answer first.

## Fast path

`checkup_state.py` keeps `~/.local/state/tooling-checkup/last-run.json`: the
time, tool versions, repository heads, the verdict, and measured numbers.
Phase 1 compares the machine with it. Use it to keep a repeat run short:

- Phase 2 has nothing to do when the inventory prints no `ship`, `salvage`,
  or `security` line, and there is no open pull request of yours on a repo
  you do not own.
- Phase 4 skips the long upgrade when the last `dotfiles-upgrade` run
  finished under 12 hours ago and Homebrew has nothing outdated (see the
  reference file). The 12-hour window counts from that run, not from the
  last checkup.
- Phase 7 replays the cached audit when no skill or rule file changed.
- Phase 6 runs the slow echo test only when `machine_metrics.py` prints
  `latency-check: run`.
- Phase 9 shows only feed items no earlier run has seen.
- Phases 1, 3, 5, 6, 8, and 9 always run. They check live state.

## Phase 1: Take stock (read-only)

```bash
python3 <skill-dir>/scripts/checkup_state.py diff
bash <skill-dir>/scripts/inventory.sh
python3 <skill-dir>/scripts/pty_capture.py --timeout 60 -- claude doctor
```

- `diff` prints the last run time, its verdict and numbers, and every tool
  version or repository head that changed since.
- `inventory.sh` prints one verdict per item: `ship`, `salvage`, `clean-up`,
  `pipeline`, `bot`, `skip`, `security`, `advisory`, or `unknown`.
- It checks pull requests and alerts on github.com and on each GitHub
  Enterprise host that `gh` is logged in to or `TOOLING_CHECKUP_GH_HOSTS`
  lists. An `unknown` line names a host it skipped and how to add it.
- `claude doctor` needs a terminal; `pty_capture.py` gives it one.

**Done when:** you have all three outputs, or you know why one failed.

## Phase 2: Ship outstanding work

Act on each inventory line by its verdict:

| Verdict | Do this |
|---|---|
| `ship` | Deliver it with `/ship-it` when it is the user's or an agent's finished work. When it is half done or you cannot tell, report it with its next step. |
| `ship` on a `PR #N` line (or `draft PR #N`) | Get it finished (below). |
| `salvage` | Look first: `git status`, `git diff`, `git stash show -p`. Commit useful work to a branch and ship it. Report what you kept. |
| `clean-up` | Delete the merged local branch (`git branch -d`, never `-D`). |
| `security` | Fix the critical alert: take the dependabot pull request or bump the package yourself. Ship it with `/ship-it`. |
| `pipeline`, `bot`, `skip`, `advisory` | Report only. |
| `unknown` | Fetch again and check by hand. Never delete. |

### Open pull requests on your repos

Each `ship  PR #N` or `ship  draft PR #N` line is an open pull request. Try
to finish it now, in a new worktree (never the live checkout), in this order
(the `wrap-up` skill's "Continue open work" section has the same steps):

1. **Draft from `wrap-up`:** read its `## Pending` list and its task. Do every
   item that is not blocked and tick it. An item only a person can do (a
   secret, a consent, a device, an approval) goes to the Phase 11
   questionnaire, and the PR stays a draft with its list up to date.
2. **Conflict:** merge the default branch into the PR branch and push.
3. **Red check:** reproduce it, fix it, push.
4. **Unresolved review thread:** change the code or answer, then resolve it.
5. **Green, nothing pending, approved where the repo needs it:** mark a
   draft ready (`gh pr ready <n>`) and merge with `/ship-it`.

A PR that only waits on a person stays open; report it with who it waits on.

### Your pull requests on tooling repos you do not own

A contributor's work sits in open pull requests on the owner's repository,
so the inventory shows no `ship` line for it. For each checkout's `origin`
(`gh repo view --json nameWithOwner,parent`; when `origin` is your fork, use
its `parent`), find the owner. Skip a repo you own: its owner equals
`gh api user --jq .login`, and the inventory already covers it. Else list
your PRs with `gh pr list --repo <owner/repo> --author @me --state open`,
then for each:

- **Red check:** fix it on the PR branch and push to your fork.
- **Unresolved review thread** (`gh api graphql`, `reviewThreads.isResolved`):
  change the code or answer, then resolve the thread.
- **Conflict:** merge the default branch into the PR branch and push. Do not
  rebase or force-push: the owner may have pushed fixes to that branch.
- **Merge** only when `gh repo view --json viewerPermission` is `ADMIN`,
  `MAINTAIN`, or `WRITE`, every check is green, and the PR is approved. Else
  leave it for the owner.

When this Mac runs a local branch that carries unmerged fixes, rebuild it
after merges: the default branch plus each fix branch still open.

**Done when:** every `ship`, `salvage`, and `security` item is merged, and
each of your open PRs is merged, or is green with zero unresolved threads, or
is a draft whose `## Pending` list holds only items a person must do, each in
the questionnaire.

## Phase 3: Refresh tooling

Read and follow the `update-tooling` skill, steps 1 to 4. It fast-forwards
clean checkouts, rebuilds the applied agentbrew, runs
`agentbrew sync --pull --no-recommended --agentfile …`,
applies dotfiles, reloads LaunchAgents, and runs the health checks. Keep its
safety rules. Its step 5 (next work) feeds this skill's report.

Time the `dotfiles apply --if-changed` step and record it in Phase 12 as
`--metric dotfiles_apply_secs=<n>`. On an unchanged machine it prints
`skipped chezmoi apply and doctor` and takes seconds. When it reports drift
(a hand-edited or missing file), name each drift line in the report.

**Done when:** `update-tooling` steps 1 to 4 are done, with each skipped
checkout, each failed check, and each drift line named.

Finish Phase 3 before you start Phase 4. The dotfiles apply and
`dotfiles-upgrade` take the same dotfiles lock; a background upgrade makes the
apply skip.

## Phase 4: Upgrade the machine

Follow [reference/machine-updates.md](reference/machine-updates.md). In short:

1. Run `dotfiles-upgrade` (Topgrade: Homebrew and casks, npm and pnpm globals,
   uv, pipx, mise, gh extensions) unless the fast path applies. Start it only
   after Phase 3 is done. Run it in the background and go on with Phases 5
   to 8. When it ends, run `dotfiles-lock-checked --log <upgrade log>`. Exit
   75 means "did not run" (a `[lock] Skipping` line and no Summary section),
   even though the upgrade exited 0: re-run it once the lock is free.
2. Run `claude update`. Compare `claude --version` before and after.
3. Run `claude doctor` again. Report every line that is not OK.
4. Check what is still outdated. Report macOS updates; never install them.

**Done when:** each package manager is upgraded, skipped with a reason, or
failed with its log lines, and the Claude Code version is verified.

## Phase 5: Background processes

Follow [reference/background-processes.md](reference/background-processes.md).
Run `scripts/background_audit.sh`. It gives each launchd job an owner and a
verdict (`remove`, `duplicate`, `off-rule`, `failing`, `review`, `keep`), and
lists the heaviest processes.

- Fix tooling-owned jobs in their source repo.
- Unload an `off-rule` minsky job at once.
- Put each third-party removal in the Phase 11 questionnaire. Disable only
  after a yes, and only by moving the plist.

**Done when:** every job that is not `keep` has an action, a question, or a
reason to leave it.

## Phase 6: Machine metrics

Read every recent machine and tooling metric in one fast pass (under a
second; it reads files the LaunchAgents already wrote):

```bash
python3 <skill-dir>/scripts/machine_metrics.py --hours 24
```

Add `--lag-reported` when the user mentions slow typing.

Overload that a known heavy foreground app explains (default: `GeForceNOW`
game streaming) is counted apart as `load_overload_rows_explained` and is
never `act`. A row counts as explained when a listed app is in its top 3
processes. `DOTFILES_EXPLAINED_LOAD` (comma or space separated) replaces the
default list; `~/.config/dotfiles/explained-load` (one name per line) adds to
it. `load_overload_rows` counts only the unexplained rows.

Each line has a verdict:

| Verdict | Do this |
|---|---|
| `act` | Find the cause (the line names the top processes or pids). Fix it in its tooling source repo with `/ship-it`, or file a task with the numbers. A third-party cause goes to the Phase 11 questionnaire. |
| `warn` | Report it. File a task when the same metric warned in the last run too. |
| `ok`, `unknown` | Report `unknown` with its note; nothing else. |

Input latency is a metric, not a ritual. Run the echo test from
[reference/input-latency.md](reference/input-latency.md) (`scripts/echo_latency.py`)
only when the script prints `latency-check: run`. Its triggers: the user
reported lag, a terminal session in the PRI 4 band, too many sessions, a large
`~/.claude.json`, orphaned temp files, or a high p95 in the last run. Then apply
only safe, reversible fixes and measure again.

**Done when:** each `act` line is fixed, filed, or in the questionnaire; and
the echo test ran with before and after numbers, or the script printed
`latency-check: skip`.

## Phase 7: Agent config audit

Follow [reference/config-audit.md](reference/config-audit.md). Run
`scripts/audit_agent_config.py --cache`, then make the judgment checks.
Ship small fixes in the source repo. Put big changes in the questionnaire.

### Monthly: new-project requirements audit

Once a month per repository, audit `agentbrew`, `dotfiles`, and `tasks.md`
(and any other tooling repository with `.agents/requirements.yaml`) against the
required areas of the `new-project` skill. Use the installed skill, or its
source in the agentbrew checkout when it is not installed:

```bash
NP=~/.claude/skills/new-project
[ -d "$NP" ] || NP="$(fd -t d -H '^new-project$' ~/apps/tooling/agentbrew -E node_modules | head -1)"
[ -n "$NP" ] && [ -f "$NP/scripts/check-setup.sh" ] || echo "new-project skill not found; skip this audit and report it"
```

1. `bash $NP/scripts/audit-due.sh <repo>`. Skip the repository when it prints `not due`.
2. `bash $NP/scripts/check-setup.sh <repo> --profile tool`. Keep the score and the `FAIL` and `WAIVED` lines.
3. Follow `$NP/references/requirements-map.md`, section 4: re-check each mapped
   file and each waiver, keep one P0 task `meet-new-project-requirements` in
   that repository's own task backend that lists every gap (remove it when the
   repository reaches 100% by intent), and turn a waiver seen in two or more
   repositories into a requirement-change proposal on `new-project`.
4. `bash $NP/scripts/audit-due.sh <repo> --record`.

### Monthly: repo health, stories, and gate speed review

In the same monthly pass, for `dotfiles` (run from its checkout):

1. Health: `bin/dotfiles-doctor --quiet`. Each failing check line names its fix.
2. Cached gate: `make check`. `bin/cached-run` skips unchanged steps;
   `make test-force` runs everything.
3. Broken stories: `make e2e`. A failing test name starts with its story ID
   (`USNN e2e: …`); report the story, not only the test.
4. Speed review: `bin/dotfiles-metrics --table`. Compare the `make check`
   row (from `~/.local/state/dotfiles/gate-timings.jsonl`) and every other
   metric with its goal and pivot. Per-step times:
   `jq -s 'group_by(.step) | map({step: .[0].step, median: (map(.seconds) | sort | .[length/2|floor])})' ~/.local/state/dotfiles/gate-timings.jsonl`.
   A metric past its pivot becomes a P0 or P1 task with the numbers.
5. Learnings: add a row to `docs/learnings.md` for each prediction closed
   since the last checkup (predicted vs observed).
6. Open P0s: list `## P0` in `TASKS.md`; each one goes to "Next: stability".
7. Changelog: `make changelog` regenerates `CHANGELOG.md` from conventional
   commits (dotfiles has no release tags, so the monthly pass is its
   release). Ship the diff as a `docs(changelog):` PR; never edit it by hand.

**Done when:** every ERROR is fixed or listed with its owner, the judgment
checks are done, each due repository has a recorded requirements audit, and
the monthly repo health line (doctor, gate, stories, gate speed) has numbers.

## Phase 8: Agent time review

agentbrew logs the time of every agent tool call (the `perf-record` hook).
Read the last 7 days, per project and overall:

```bash
python3 <skill-dir>/scripts/agent_time_review.py --days 7
```

It wraps `agent-perf.mjs report --all --days 7 --json` and the
`session-report` analyzer (tokens and hours). It prints the top 3 slowest
recurring steps (2 or more calls) per project and overall, a `fix:` line for
each step that matches a known safe fix, the change since the last checkup,
and one speedup line per step that recurs in 2 or more sessions and costs
1 min/day or more. A step repeated inside one session is not a task:

| Line | Do this |
|---|---|
| `file` | Add the task id to that tooling repo's `TASKS.md`, with the step, its cost per day, and the fix. Ship it in Phase 12. |
| `filed` | The task exists. Re-rank it when the cost grew. |
| `report` | Not a tooling repo. Report it only. |
| `inspect` | The key is redacted. Find the real step with `agent-perf.mjs report --session <id>`, then file or report it. |

Known fixes: a polling loop becomes a blocking wait; a repeated full install
is skipped when the lockfile is unchanged; a full gate in the inner loop uses
affected-test selection; a test runner at PRI 4 is on background QoS. In a
tooling repo, ship a small fix with `/ship-it`. Put a big one in the
questionnaire. Use the perf-review skill for deeper analysis.

**Done when:** the review is printed with real numbers, and each `file`,
`filed`, `report`, and `inspect` line has an action.

## Phase 9: AI-work research

Look for new ways to work with AI, on your own, every run. Follow
[reference/ai-work-research.md](reference/ai-work-research.md). In short:

1. Run `python3 <skill-dir>/scripts/ai_research.py scan` outside the sandbox.
   It prints only feed items that no earlier run has seen. Add up to two web
   searches for what the feeds miss.
2. Ask the Altitude question about the top recurring step from Phase 8: what
   outcome could an agent own instead of this step?
3. Judge each candidate with one lens (Speed, Altitude, Depth, Range) and one
   verdict: `adopt`, `try`, or `skip`. Read only; install nothing from a post.
4. Each `adopt` or `try` names its metric and command (an outside judge),
   then becomes a `/ship-it` change, a task, or a Phase 11 question.

**Done when:** the scan ran (or each feed error is named), each new item has
a verdict line, and each `adopt` or `try` has a task, a change, or a question.

## Phase 10: Report

The report is one self-contained HTML page, not chat text (shared-rules
**## Long-run reports**). Build it from the outline below, verdict first:

1. Write it to `~/.local/state/tooling-checkup/reports/<YYYY-MM-DD>.html`.
   Load the `artifact-design` skill first when the Artifact tool exists.
2. Show paths as `~/…` and keep secrets, tokens, and private names out.
   Then publish it as a private Artifact (the Artifact tool). Without the
   Artifact tool, send the file (SendUserFile) or give its full path.
3. Each "Needs you" item and each blocker says, in plain words, what it is,
   why it is blocked, the options, and what each option changes.
4. In chat, write only the page link, the one-line verdict, and then go to
   Phase 11. Do not paste the whole report.

Outline of the page:

```markdown
## Tooling checkup <YYYY-MM-DD>

**Verdict:** <healthy | healthy with gaps | broken: <what>>
**Since last run (<age>):** <changed versions and heads, or "nothing changed">

### Shipped
- <PR or commit>: <what it delivers> (<evidence>)

### Updated
- <tool>: <old> → <new> | skipped: <reason> | failed: <log line>
- Claude Code: <old> → <new>; doctor: <OK or findings>

### Background processes
- Removed: <label> (<why>) · Kept for you to decide: <label>
- Heavy: <process> <cpu>% <mem> MB → <cause or lead>

### Machine metrics (24 h)
- act: <metric> <value> → <fix, task, or question> · warn: <metric> <value> · rest ok
- Input latency: skipped (no trigger) | claude p95 <before> → <after> ms (<trigger>)

### Config audit
- <n> errors, <n> warnings · fixed: <list> · open: <list with owner>
- Requirements (monthly): <repo> <score> (<change>) · waived: <n> · not due: <repos>
- Repo health (monthly): doctor <n> failing · gate <pass/fail> · stories broken: <USNN list or none> · gate <median> s (goal 120, pivot 300)

### Agent time (7 days)
- Tool time: <h> (<change> vs last run) · active <h> · output <n>M tokens
- Slowest recurring: <key> <total> (<n>x, p95 <s>) · <key> … · <key> …
- Per project: <project>: <top key> <total> · …
- Speedups: filed <repo>/<task-id> (<min/day>) · fixed: <what> · none

### AI-work research
- Scanned: <n> new items from <n> feeds (<errors>) · searches: <queries>
- Adopt/try: <idea> (<lens>) → <task, PR, or question> · skipped: <n>

### Needs you
- <item> → <the exact question or command>

### Next: stability
1. `<repo>/<task-id>` (<priority>): <why now>

### Next: features
1. `<repo>/<task-id>` (<priority>): <why now>
```

Rules: "Shipped" lists only work that reached `origin`. Keep stability and
feature work in separate lists, up to three each. Recommend from the refreshed
`TASKS.md` queues of the tooling repositories. A gap with no task gets
`new: <kebab-case-id>` and one line on why.

**Done when:** the HTML page is published (or its path given), each claim on
it has evidence, and the chat holds only the link and the verdict.

## Phase 11: Ask the owner

Ask from the page: each question names the page section it comes from.
Collect the questions: each "Needs you" item, each third-party job to remove,
each big config change, and which next tasks to start. Skip a question an
earlier answer settles.

Ask with `AskUserQuestion`, up to 4 questions per call, in rounds. For each
question:

- **Context:** what it is, what is true now, and the evidence.
- **Options:** 2 to 4 concrete choices. Each says what you will do and what it
  costs. Put your recommendation first, with "(Recommended)" in its label.
- The header has 12 characters or fewer.

**Done when:** every question has an answer, or the user chose to stop.

## Phase 12: Apply the answers and record

1. Apply each answer: disable the approved jobs, ship the approved config
   changes with `/ship-it`, and file or re-rank tasks (with the Phase 8
   speedup tasks and the Phase 9 research tasks).
2. Run `bash <skill-dir>/scripts/inventory.sh` again and update the report.
   Mark the Phase 9 items as seen: `python3 <skill-dir>/scripts/ai_research.py record`.
3. Record this run:

   ```bash
   python3 <skill-dir>/scripts/checkup_state.py record --verdict "<verdict line>" \
     <the Phase 6, 8, and 9 `record:` metrics> --metric dotfiles_apply_secs=<n> \
     [--metric claude_echo_p95_ms=<n> --metric shell_echo_p95_ms=<n> when the echo test ran]
   ```

   `--metric` takes `key=value` only, one per flag. A bare value fails with
   "unrecognized arguments". Example: `--metric shell_echo_p95_ms=42`.

**Done when:** each answer is applied or listed with a reason, and the state
file holds this run.

---
name: tooling-checkup
description: >
  One-command health pass for the tooling repositories and the whole Mac. Ships
  outstanding tooling work, refreshes the tooling checkouts and agent config,
  upgrades Homebrew, npm, uv, pipx, mise, and Claude Code, runs `claude doctor`,
  audits LaunchAgents and heavy processes, measures Claude Code input latency
  in Ghostty, and lints skills, rules, and AGENTS.md files against Anthropic's
  best practices. Then it reports what changed since the last run, asks the
  owner a questionnaire, and applies the answers. Use when the user runs
  "/tooling-checkup", or asks to update all tooling and the machine, to tidy up
  background processes, or to check that agent config follows best practices.
  Don't use for a refresh without package upgrades (use update-tooling) or for
  one task in one repository (use ship-it).
disable-model-invocation: true
---

# Tooling checkup

The user runs this by hand every 2 or 3 days. It must be safe to repeat, and
fast when nothing changed. Run ten phases in order. Each phase ends with a
**Done when** check. Phases 8, 9, and 10 always run, even when an earlier
phase is blocked.

`<skill-dir>` below means this skill's base directory.
`TOOLING_ROOT` defaults to `~/apps/tooling`.

**Scope.** `/tooling-checkup` alone runs all ten phases. A request for one part
runs Phase 1, that part, and Phases 8 to 10:

| The user asks to… | Run |
|---|---|
| ship what is pending in tooling | Phase 2 |
| update tooling and the machine | Phases 3 and 4 |
| clean up background processes | Phase 5 |
| make Claude Code typing faster | Phase 6 |
| check skills and rules against best practices | Phase 7 |

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
5. **Source, not output.** Generated agent config (`~/.claude/`, `~/.cursor/`,
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
  or `security` line.
- Phase 4 skips the long upgrade when the last upgrade is under 12 hours old
  and Homebrew has nothing outdated (see the reference file).
- Phase 7 replays the cached audit when no skill or rule file changed.
- Phases 1, 3, 5, and 6 always run. They check live state.

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
- `claude doctor` needs a terminal; `pty_capture.py` gives it one.

**Done when:** you have all three outputs, or you know why one failed.

## Phase 2: Ship outstanding work

Act on each inventory line by its verdict:

| Verdict | Do this |
|---|---|
| `ship` | Deliver it with `/ship-it` when it is the user's or an agent's finished work. When it is half done or you cannot tell, report it with its next step. |
| `salvage` | Look first: `git status`, `git diff`, `git stash show -p`. Commit useful work to a branch and ship it. Report what you kept. |
| `clean-up` | Delete the merged local branch (`git branch -d`, never `-D`). |
| `security` | Fix the critical alert: take the dependabot pull request or bump the package yourself. Ship it with `/ship-it`. |
| `pipeline`, `bot`, `skip`, `advisory` | Report only. |
| `unknown` | Fetch again and check by hand. Never delete. |

**Done when:** every `ship`, `salvage`, and `security` item is merged, or it
is listed with its reason and next step.

## Phase 3: Refresh tooling

Read and follow the `update-tooling` skill, steps 1 to 4. It fast-forwards
clean checkouts, rebuilds the applied agentbrew, runs `agentbrew sync --pull`,
applies dotfiles, reloads LaunchAgents, and runs the health checks. Keep its
safety rules. Its step 5 (next work) feeds this skill's report.

**Done when:** `update-tooling` steps 1 to 4 are done, with each skipped
checkout and each failed check named.

## Phase 4: Upgrade the machine

Follow [reference/machine-updates.md](reference/machine-updates.md). In short:

1. Run `dotfiles-upgrade` (Topgrade: Homebrew and casks, npm and pnpm globals,
   uv, pipx, mise, gh extensions) unless the fast path applies. Run it in the
   background and go on with Phases 5 to 7.
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
- Put each third-party removal in the Phase 9 questionnaire. Disable only
  after a yes, and only by moving the plist.

**Done when:** every job that is not `keep` has an action, a question, or a
reason to leave it.

## Phase 6: Claude Code input latency

Follow [reference/input-latency.md](reference/input-latency.md). Measure with
`scripts/echo_latency.py` (three runs of `zsh -f` and of `claude`). Collect the
causes: open sessions, load, `~/.claude.json` size, orphaned temp files, the
status line, the Ghostty config. Apply only safe, reversible fixes, then
measure again.

**Done when:** you have before numbers, and after numbers for each change you
made. With no change, report the numbers and the top cause.

## Phase 7: Agent config audit

Follow [reference/config-audit.md](reference/config-audit.md). Run
`scripts/audit_agent_config.py --cache`, then make the judgment checks.
Ship small fixes in the source repo. Put big changes in the questionnaire.

**Done when:** every ERROR is fixed or listed with its owner, and the judgment
checks are done.

## Phase 8: Report

Put the verdict first. Use this template.

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

### Input latency
- claude p95: <before> → <after> ms · shell p95: <n> ms · sessions: <n>

### Config audit
- <n> errors, <n> warnings · fixed: <list> · open: <list with owner>

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

**Done when:** the report is written and each claim has evidence.

## Phase 9: Ask the owner

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

## Phase 10: Apply the answers and record

1. Apply each answer: disable the approved jobs, ship the approved config
   changes with `/ship-it`, and file or re-rank tasks.
2. Run `bash <skill-dir>/scripts/inventory.sh` again and update the report.
3. Record this run:

   ```bash
   python3 <skill-dir>/scripts/checkup_state.py record --verdict "<verdict line>" \
     --metric claude_echo_p95_ms=<n> --metric shell_echo_p95_ms=<n> --metric claude_sessions=<n>
   ```

**Done when:** each answer is applied or listed with a reason, and the state
file holds this run.

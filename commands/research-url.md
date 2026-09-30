---
description: Research a URL, product name, or text and file evidence-backed tasks in the tooling repos
argument-hint: "<url | product name | text>"
---

# Research URL / Product to Tooling Tasks

Take one raw input string. It may be:

- a direct URL;
- prose containing one or more URLs;
- a product, library, tool, paper, or technique name with no URL.

Research the source deeply, compare it against the user's active tooling repos, then add `TASKS.md` entries only where there is concrete evidence-backed fit. The command succeeds even when the result is zero filed tasks.

## Canonical target repos

Consider exactly these repos unless the user explicitly names more:

| Repo | Path | Fit boundary |
|---|---|---|
| `dotfiles` | `~/apps/tooling/dotfiles` | macOS/dev-machine config, shell/git wrappers, launchagents, doctor checks, agent-tool bootstrap. |
| `agentbrew` | `~/apps/tooling/agentbrew` | Cross-agent sync for skills, MCP servers, rules, commands, hooks, agents, instructions, catalogs. |
| `minsky` | `~/apps/tooling/minsky` | Autonomous loop, supervisor/orchestrator, cross-repo runner, observer, task-picking, agent backends. |

Do not silently expand the target list. If the source appears relevant only to another repo, say so in the summary and skip filing unless the user approves that repo.

## Iron rules

1. **No padding.** Consider every target repo, but file a task only when the fit is Strong or Modest. A clear skip reason is better than a weak task.
2. **Every filed task needs repo file:line evidence.** Cite the source URL or product research evidence plus the local repo file and line that proves the gap. If you cannot produce local file:line evidence, skip.
3. **Read-only before task edits.** Research and repo assessment are read-only. Do not edit code; only edit `TASKS.md` after a repo passes the fit gate.
4. **One task per repo per invocation.** If one repo has several possible ideas, file the highest-value one and put the rest under an explicit "Out of scope / future candidates" sentence in the task body.
5. **Respect repo rules.** Load each repo's `AGENTS.md` and task format before editing. Match its priority semantics, branch policy, and lint command.
6. **No destructive git.** Never use `git reset --hard`, `git checkout .`, `git clean -fd`, `git stash`, `git add -A`, `git add .`, or `git add -u`.
7. **Stage only `TASKS.md`.** If committing, use `git add TASKS.md` or `git commit --only TASKS.md`.
8. **Standing delivery approval for this command.** The user has pre-approved this command to make scoped local changes, commit, push, open PRs, merge, and deploy/sync for the canonical target repos listed above, provided the change is the `TASKS.md`-only task-filing output of this workflow (or this command's own source/evals when maintaining `/research-url`). This approval does not cover destructive git, force/history rewrites, protected-branch direct pushes, package releases, public comments/reviews, Slack/Jira/email messages, secrets, production data changes, or repos outside the canonical target list unless the user names them in the invocation.

When `/research-url` is active, read and follow **`~/apps/tooling/dotfiles/docs/research-url-reference.md`** end-to-end (Phases 0–4, summary format, anti-patterns, examples). Execute without re-prompting unless repo-local rules block task filing.

<!-- turbo -->

Quick index (detail in reference): normalize input → research source → repo fit → draft tasks → optional delivery → summary.

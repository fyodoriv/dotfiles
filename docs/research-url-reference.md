# Research URL — workflow reference

## Phase 0 — Normalize input

1. Capture the full `$ARGUMENTS` string. If empty, ask for one URL, product name, or text snippet.
2. Extract URLs from the input. If URLs exist, treat them as primary sources.
3. If no URL exists, use web search with simple focused queries:
   - `<product name> official`
   - `<product name> GitHub`
   - `<product name> documentation`
4. If the name is ambiguous after search, ask one clarifying question and recommend the most likely target.
5. If the user supplied prose with several URLs, cap primary sources at the three most substantive links unless it is an aggregator/newsletter, where Phase 1.5 applies.

## Phase 1 — Research the source

For each primary source:

1. Fetch or open the URL with the available web/browser tooling. For dynamic pages, use browser automation rather than declaring it blocked. For SSO-gated pages, use isolated SSO browser handling.
2. Identify the content shape:
   - tool/library/repo;
   - docs/tutorial;
   - paper/spec;
   - incident/postmortem;
   - aggregator/newsletter/link roll;
   - discussion thread.
3. For tool/library/repo sources, verify install path, license, runtime requirements, last release/activity, and whether it is a CLI, MCP server, skill, command, hosted API, or methodology.
4. For papers/specs, read abstract/intro and related work to identify what is genuinely new.
5. For discussion threads, read high-signal comments about failure modes, limits, and competing tools.
6. Write private working notes with:
   - what this concretely is;
   - the problem it solves;
   - the cheapest test against the user's tooling stack;
   - maturity/red flags;
   - likely target repos, if any.

## Phase 1.5 — Follow inner links for aggregators

For newsletters, digests, link rolls, and other aggregators:

1. Identify up to eight substantive items. Prefer CLI tools, MCP servers, agent skills, harnesses, sandboxing patterns, workflow methods, specs, or reproducible techniques.
2. Fetch each item's underlying source. Never decide from the aggregator blurb alone.
3. Skip marketing-only blurbs, funding/news announcements, opinion posts without a concrete technique, and gated sources that cannot be verified.
4. Before treating a tool as new, search each target repo's `TASKS.md` plus relevant catalogs/docs for the product name and common aliases.

## Phase 2 — Repo fit assessment

Assess the three repos in this order:

1. `dotfiles` — does this improve machine bootstrap, doctor checks, shell/git safety, browser/tool setup, or agent-tool lifecycle?
2. `agentbrew` — does this belong as a cross-agent sync/catalog/deployment capability, or as a command/skill/source pattern? Prefer "curate/wrap" over "host/absorb".
3. `minsky` — does this improve autonomous loops, orchestration, agent backend adapters, task selection, supervision, observability, or long-running resilience?

For each repo, produce one verdict:

- **Strong fit** — repo file:line evidence proves a real gap and the task is small enough to file now.
- **Modest fit** — evidence shows adjacency but the right next step is a spike with explicit absorb/defer/reject outcomes.
- **Skip** — weak fit, policy conflict, duplicate existing task, no local file:line evidence, or source is too immature.

## Phase 3 — Draft and insert tasks

For each Strong or Modest repo:

1. Read that repo's `TASKS.md` and `AGENTS.md`.
2. Check for duplicates by searching `TASKS.md`, docs, and relevant catalogs for the product/tool/technique name and aliases.
3. Draft one task in the repo's local format. Include:
   - unique kebab-case `ID`;
   - appropriate priority;
   - tags;
   - source evidence;
   - local repo file:line evidence;
   - details explaining why this repo is a fit;
   - explicit out-of-scope / future candidates;
   - concrete acceptance criteria.
4. Insert at the correct priority section.
5. Lint the task file with the repo's required command. If none is documented, use `npx @tasks-md/lint TASKS.md`.
6. If lint fails because of the new task, fix and re-run. If lint fails only because of unrelated pre-existing tasks, revert the new edit for that repo and report the blocker.

## Phase 4 — Optional commit / delivery

For each repo with a task edit:

1. Run `git status --short --branch` and inspect for unrelated work.
2. If the checkout is dirty with unrelated work, prefer creating an isolated worktree from the repo's default branch. If that is not safe, skip the repo with a clear reason.
3. Stage only `TASKS.md`.
4. Commit when repo-local rules permit it. The standing delivery approval above satisfies the "explicit approval" requirement for scoped `TASKS.md` task-filing commits in `dotfiles`, `agentbrew`, and `minsky`. Use the repo's commit format. If no stricter format exists, use:
   - `chore: add research task <task-id> PROJ-123`
5. Push, open a PR, wait for required checks, merge, and run the repo-local deploy/sync step when repo-local rules allow it. For this command, the user has already granted that approval for the three canonical target repos; do not stop at "local diff only" solely because the repo is a sibling checkout or a worktree created during this workflow.
6. If repo-local protection blocks merge/deploy (red checks, missing credentials, branch protection, auth errors, required human review), report the blocker with the PR URL and exact evidence. Do not bypass hooks, force-push, admin-merge, or publish public comments/reviews unless the user separately approves that exact action.

## Summary format

Always end with:

```text
Source: <input> — <one-line researched synopsis>

Per-repo verdicts:
  dotfiles  → <added | local-only | skipped — reason>
  agentbrew → <added | local-only | skipped — reason>
  minsky    → <added | local-only | skipped — reason>

Tasks filed:
  <repo>: <task-id> — <merged PR URL | open PR URL + blocker | commit hash>
  ...

Verification:
  <repo>: <TASKS.md lint command> — <pass/fail/blocker>
```

If zero tasks were filed, include the three skip reasons and stop. Zero tasks is a valid outcome when the research does not clear the evidence bar.

## Anti-patterns to refuse

- Filing tasks from an aggregator blurb without fetching the underlying source.
- Filing "consider adopting X" with no local file:line evidence.
- Adding one task to every repo just because every repo was considered.
- Re-filing an already tracked product or idea.
- Adding code changes while researching; this command files tasks, not implementations.
- Treating a web UI as human-blocked before trying browser automation.
- Publishing outside the canonical target repos, force/history-rewriting, protected-branch pushing, or posting public comments/reviews by relying on the standing delivery approval. It is scoped to this command's task-filing PRs/merges/deploys only.

## Invocation examples

```text
/research-url https://example.com/tool
/research-url "look into mempalace and add tooling tasks if it fits"
/research-url "This post says https://example.com/blog/agent-sandbox prevents runaway agents"
```

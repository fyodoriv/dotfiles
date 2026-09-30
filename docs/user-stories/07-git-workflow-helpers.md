# User Story: Git Workflow Helpers

> Create PRs, hotfixes, and code reviews — one command each, no ceremony.

## Create a PR

```bash
pr "feat: add login flow"   # commit, push, draft PR via gh
pr                           # uses last commit message as title
```

Stages tracked changes (`git add -u`), commits, pushes, and creates a draft PR via `gh pr create --draft` (or opens the existing PR in your browser if one already exists). Refuses to run from `main`/`master`.

## Agent delivery in tooling repos

For any git repo under `~/apps/tooling`, an agent-owned change is complete only after the agent has run relevant verification, committed the scoped files, pushed the feature branch, opened a PR, watched/read CI, and merged the PR once checks are green. Stopping at "verified but uncommitted" or "PR opened" is incomplete unless a blocker is documented.

## Hotfix from Main

```bash
hotfix "fix: resolve crash on startup"
```

Stashes current work, detects the default branch (`main` or `master`), pulls latest, creates a `hotfix/fix-resolve-crash-on-startup` branch, and pops the stash. You make your fix, then `pr` to ship it.

## Review a PR

```bash
review 123    # checkout PR #123, show diff, prompt to run tests
review        # list open PRs to pick from
```

Checks out the PR branch, shows the diff summary, then prompts before running the test suite (`make test` or `npm test`) and before opening the PR page in your browser. Press `n` (or wait 30s) to skip either step.

## Other Helpers

| Command | What it does |
|---------|-------------|
| `new-project <template> <name>` | Scaffold a project (templates: `react`, `node`, `lib`, `python`) with `git init` + `.gitignore` |
| `note [text]` | Quick timestamped notes (daily files in `~/.notes/<date>.md`) |
| `timer <duration>` | Pomodoro-style timer with notification |

## Files Involved

| File | Purpose |
|------|---------|
| `bin/pr` | PR creation helper |
| `bin/hotfix` | Hotfix branch workflow |
| `bin/review` | PR checkout + review |
| `bin/new-project` | Project scaffolding |
| `bin/note` | Quick notes |
| `bin/timer` | Timer utility |

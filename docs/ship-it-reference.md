# Ship It — full delivery reference

Companion to the `/ship-it` slash command. When ship-it mode is active, execute these steps in order.

## Session activation

**One `/ship-it` per conversation is enough.** The first invocation in a Cursor chat enables ship-it mode for the rest of that session. Agents must scan conversation history for an earlier `/ship-it` before asking the user to re-invoke the command. **Forked subagents inherit the same mode** — a parent-chat `/ship-it` counts; never require a second invocation.

Mode remains active until the user says **stop ship-it** or applies a narrow exception (plan only, read only, no commit, no push, scoped file/repo). While mode is on, run Steps 1–13 without re-prompting for commit, push, PR, merge, or Steps 12–13.


## Planning requests

Use this section only when the active request is to create or revise a plan. It
does not add a planning stop before an explicitly requested implementation or
delivery.

1. Read `writing-plans` before authoring.
2. For a docs-hub, multi-repo, host-integration, state, Jira, or Google Doc
   plan, also read `task-command-center` and
   `references/implementation-plan-template.md`.
3. Lead with **Overall goal and vision**: the user outcome, why it is needed
   now, the current constraint, and the durable capability being created.
4. Compare material alternatives and state why the selected direction is
   preferable. Keep source-backed facts separate from proposals and include a
   ledger with the current source of each required datum and its delivery path.
5. Use a numbered work breakdown. Every task includes **Why**, dependency or
   parallelism, owner/boundary, concrete change, acceptance evidence, and an
   exact verification. Name parallel lanes explicitly.
6. For host or embedded-surface work, define a versioned
   `HostBootstrapPayload`: ownership, schema/version, transport, origin and
   schema validation, correlation/sequence behavior, reset on record change,
   error/retry UX, and where Redux ownership differs from domain-state
   provenance.
7. End with rollout/merge order, security, unit/contract/integration/end-to-end
   regression coverage, and unresolved decisions with their owners.

## Session auto-ship (default)

**Default behavior:** `/ship-it` means automatically inventory and ship **all** user-owned / current-session pending work in the current repo, repositories explicitly named by the active request, and approved repo families. Do not stop at "ready to commit" or "PR opened" unless a **dangerous** blocker applies. Do not ask for re-approval on approved actions.

### Invocation examples

| Invocation | Behavior |
|---|---|
| `/ship-it` | Ship everything pending from this session in the current repo, explicitly named current-task repos, and every approved-family sibling repo, one repo at a time, through the applicable Steps 1–13 |
| `/ship-it fix lint errors` | Scoped task, but still auto-delivers that scope end-to-end (verify → commit → PR → CI → merge → Steps 12–13) without commit/push prompts |
| `/ship-it stop` or "plan only" / "no push" | Narrow exception — honor the limit for that scope only; resume auto-ship afterward unless ship-it mode is disabled entirely |

### Auto-ship scope (no re-prompt)

- all user-owned/current-session changes in the current repo and explicitly named current-task repos; plus sibling inventory in approved tooling, own-repo, and overlay-declared families
- normal feature-branch push, PR create/update, CI watch/fix, and safe rebase publication for verified user-owned/current-session work in those current-task repos
- TASKS.md P0/P1 actionable items tied to the current session
- cross-repo delivery, salvage-first worktree handling, then ship
- verify → commit → push/PR → CI watch/fix → bypass merge cascade when green + `REVIEW_REQUIRED` only **and** repo is on the bypass allowlist (see § Repo bypass allowlist)
- Steps 12–13 machine refresh — **agent executes via Shell** (`git pull`, `dotfiles apply`, `bin/dotfiles-reload-launchagents`, CDP verify, enable optional token runtime tools, `agentbrew sync --pull`, `npm run build` when agentbrew shipped, `agentbrew measure context`, doctor); never user-delegated

### Dangerous — stop and report (do NOT auto-proceed)

- plain `git push --force`, unleased history rewrites, protected-branch direct pushes
- hook bypasses (`--no-verify`, `--no-gpg-sign`, etc.)
- admin/bypass merge before green checks, on a non-mergeable PR, on someone else's PR, or on **non-allowlist** repos (bypass denied — normal merge + report only)
- deleting unsalvaged worktrees/branches or other agents' work
- secrets/credentials commits
- cross-workspace publish outside explicitly named current-task repos and approved families
- production deploy outside the own-tool allowlist unless documented and explicitly requested
- dropping unpreserved default-branch commits
- actions requiring human UI (OTP, Slack approval, physical authenticator, etc.) — write the `avoid-human-blocked-actions` doc, then stop with the exact step

### Dangerous blocker output format

When a dangerous action blocks delivery, stop with:

1. **Blocker category** (e.g. "human UI required", "secrets in diff", "someone else's PR")
2. **Exact command or UI step** that would be needed
3. **Why no safer path exists** (what was already tried)
4. **Delivery status** — what was already shipped in this session vs what remains blocked

Example:

```text
SHIP-IT BLOCKED (dangerous): human UI required

Blocker: npm publish needs OTP for @scope/package
Command: npm publish --otp=<code> (requires authenticator approval)
Safer path exhausted: workflow publish.yml failed on OTP; local publish blocked without OTP
Already shipped: dotfiles PR #1234 merged; agentbrew PR #567 merged
Remaining: tasks-md release v1.2.3 (npm publish blocked)
```

## Delivery report honesty (IRON LAW)

`/ship-it` delivery reports must reflect **actual merge outcomes**, not aspirational completion.

**Required:**
- Headline with counts: **`Merged N/M PRs`** (M = session PRs in scope across approved families)
- Per-PR status: merged / open-pending-review / open-pending-CI / blocked-with-reason
- PR URLs for every open PR
- Steps 12–13 evidence for repos that **did** merge (when tooling delivery applies)

**Forbidden:**
- "Ship-it complete", "Delivery complete", or "All PRs shipped" when **any** session PR remains open
- Stopping after the first review-gate failure without processing remaining PRs in scope
- Asking "should I merge?" — `/ship-it` is standing approval; try every allowed merge API first

**Partial delivery is valid.** When a `required_pull_request_reviews` rule blocks merge, report partial delivery honestly and continue rebase/CI work on review-blocked PRs in the same session.

Example when review blocks remain:

```text
SHIP-IT PARTIAL (review gate): Merged 2/5 PRs

Blocker category: required_pull_request_reviews (cannot bypass)
Exact error: gh pr merge 584 --admin → Review required
Safer path exhausted: normal merge, --admin merge, auto-merge all rejected

Merged:
- dotfiles #456 (admin bypass — tooling repo)
- example-tool #120 (squash)

Pending review only (CI green, mergeable):
- example-app #584 — <PR URL>
- example-app #122 — <PR URL>

Agent continued: rebased #584 onto main; fixed CI on #122
Human action: a teammate with write access must approve PRs #584, #122

Steps 12–13: executed for merged repos (evidence below)
```

## Repo bypass allowlist (run before merge)

`/ship-it` **auto bypass-merge** applies only when the repo is on the allowlist below. **Default for every other repo is DENY bypass** — ship commit/PR/CI still runs, but agents do **not** attempt `--admin`, self-approve, or GraphQL bypass; report `REVIEW_REQUIRED` and list PR URLs.

### ALLOW bypass cascade (`BYPASS_ALLOWED=true`)

Run the full **bypass merge cascade** (§ below) when substantive checks are green, the PR is mergeable, and `reviewDecision` is `REVIEW_REQUIRED` (only blocker).

| Rule | Match |
|------|--------|
| **tooling family** | Real path under `~/apps/tooling/**` (`agentbrew`, `dotfiles`, `tasks-md`, `minsky`, …) |
| **Own repos** | Repo name `agentbrew`, `dotfiles`, `tasks-md`, `tasks.md`, or `minsky`; **or** `origin` matches `github.com:<owner>/*` / `github.com/<owner>/*` for the authenticated owner |
| **Overlay-declared families** | Extra repo families the org overlay declares, for example through `SHIP_IT_EXTRA_REPO_FAMILIES` (a colon-separated list of path globs). This page only documents the variable. The base repo ships no code that reads it; the overlay's ship-it rules do |

A host's branch protection may still reject the bypass APIs when `required_pull_request_reviews` has no actor allowance. Agents **run the full cascade anyway** on allowlisted repos and report honestly.

### DENY bypass (`BYPASS_ALLOWED=false`) — default

Any repo **not** matching ALLOW above.

- **Still ship:** inventory → verify → commit → push → PR → CI watch/fix → **normal merge only** (cascade step 1).
- **Do not run** cascade steps 2–6 (`--admin`, self-approve, GraphQL, REST bypass).
- Report `REVIEW_REQUIRED` with PR URLs; continue other session PRs.

### Detection (agents run per repo before Step 7)

```bash
REPO_ROOT=$(cd "$(git rev-parse --show-toplevel)" && pwd)
REPO_NAME=$(basename "$REPO_ROOT")
REMOTE_URL=$(git remote get-url origin 2>/dev/null || true)
OWNER="${SHIP_IT_OWNER:-$(gh api user -q .login 2>/dev/null)}"

BYPASS_ALLOWED=false
case "$REPO_ROOT" in
  */apps/tooling/*) BYPASS_ALLOWED=true ;;
esac
case "$REPO_NAME" in
  agentbrew|dotfiles|tasks-md|tasks.md|minsky) BYPASS_ALLOWED=true ;;
esac
[ -n "$OWNER" ] && [[ "$REMOTE_URL" =~ github\.com[:/]${OWNER}/ ]] && BYPASS_ALLOWED=true
# Overlay-declared families: match $REPO_ROOT against each glob in
# $SHIP_IT_EXTRA_REPO_FAMILIES (colon-separated), when the overlay sets it.

echo "ship-it bypass allowlist: BYPASS_ALLOWED=$BYPASS_ALLOWED repo=$REPO_NAME root=$REPO_ROOT"
```

Record `BYPASS_ALLOWED` in the delivery report for each repo shipped.

## Review gate (branch protection)

Some hosts enforce `required_pull_request_reviews`. Behavior depends on **§ Repo bypass allowlist**:

- **Allowlist repos** (tooling, own repos, overlay families): run the full bypass cascade; do not stop after the first `REVIEW_REQUIRED`.
- **Other repos**: bypass denied — normal merge only; report pending review.

**Policy facts:**
- Self-approval is forbidden — `gh pr review --approve` on your own PR → `Can not approve your own pull request`
- `gh pr merge --admin`, GraphQL `mergePullRequest`, and REST `PUT .../merge` enforce the same gate → `At least 1 approving review is required by reviewers with write access`
- Admin rights often do not bypass `required_pull_request_reviews` — cascade steps may all fail until a teammate approves
- Stale head vs base blocks merge APIs until the branch is updated — run cascade step 0 first

**Contrast with own-tool repos:** In `~/apps/tooling/**` (`agentbrew`, `dotfiles`, `tasks-md`, `minsky`), cascade step 2 (`--admin`) or step 5 (GraphQL) is usually the completion path when `reviewDecision: REVIEW_REQUIRED` is the only blocker.

## Bypass merge cascade (mandatory under `/ship-it` when `BYPASS_ALLOWED=true`)

When `BYPASS_ALLOWED=true` and a session-owned PR has green substantive checks and `reviewDecision: REVIEW_REQUIRED`, ship-it mode **MUST run every step below** before treating review as irreducible. **Never stop** after the first `REVIEW_REQUIRED` from `gh pr merge --admin` — continue through self-approve, GraphQL, and REST. Record each command and its stderr/JSON error in the delivery report.

When `BYPASS_ALLOWED=false`, run only cascade **step 0** (update branch if stale) and **step 1** (normal merge); skip steps 2–6.

**Preconditions (verify before the cascade):**

```bash
gh pr view <n> --json author,headRepositoryOwner,headRefName,reviewDecision,mergeable,statusCheckRollup
# Author/head must be session-owned. Substantive checks green (skip *e2e* / *automation* pending).
```

**Set the host** when `git remote get-url origin` is not `github.com`:

```bash
export GH_HOST=<your-github-host>   # match remote host — required for gh api/graphql on GitHub Enterprise
OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)
PR=<number>
```

**Cascade** — run in order; stop only when `gh pr view <n> --json state -q .state` is `MERGED`:

```bash
# 0. Update branch when mergeable is false due to stale head (not CONFLICTING)
# Prefer gh pr update-branch when available; otherwise rebase + --force-with-lease per Inventory rewrite rules.
gh pr update-branch "$PR" --rebase 2>/dev/null || true

# 1. Normal squash merge
gh pr merge "$PR" --squash --delete-branch 2>&1 || true

# 2. Admin merge (GitHub uses GraphQL mergePullRequest internally)
gh pr merge "$PR" --squash --delete-branch --admin 2>&1 || true

# 3. Auto-merge when supported (queues merge after requirements)
gh pr merge "$PR" --auto --squash --delete-branch 2>&1 || true

# 4. Self-approve then merge — try even when policy likely forbids it
gh pr review "$PR" --approve 2>&1 && gh pr merge "$PR" --squash --delete-branch 2>&1 || true

# 5. GraphQL mergePullRequest (explicit — same review gate as step 2)
PR_ID=$(gh pr view "$PR" --json id -q .id)
gh api graphql -f query='
mutation($id: ID!) {
  mergePullRequest(input: {pullRequestId: $id, mergeMethod: SQUASH}) {
    pullRequest { merged url mergeCommit { oid } }
  }
}' -f id="$PR_ID" 2>&1 || true

# 6. REST merge (explicit — same review gate as step 2)
gh api -X PUT "repos/$OWNER/$REPO/pulls/$PR/merge" -f merge_method=squash 2>&1 || true
```

Use `merge_method=merge` or `rebase` only when the repo's default merge method requires it.

**When each step typically succeeds vs fails:**

| Step | Allowlist repos | Other repos |
|------|-----------------|-------------|
| 0 | When head behind base | Same (if merge attempted) |
| 1 | When review already approved | **Only bypass step allowed** |
| 2 | **Usually succeeds** when checks green + only review blocked; may fail under strict protection — run anyway | **Skipped** — bypass denied |
| 3 | When auto-merge enabled | **Skipped** |
| 4 | May succeed when author approval allowed | **Skipped** |
| 5–6 | Fallback; often same as step 2 | **Skipped** |

**Irreducible human review** (report honestly after the **full** cascade on allowlist repos, or after step 1 on other repos):

- `required_pull_request_reviews` with no bypass allowance for the actor
- Pending **CODEOWNERS** review from another team (merge blocked even with one generic approval)
- PR author cannot self-approve and no teammate approval on the PR

**Not irreducible** — keep working instead of filing human-blocked:

- Head behind base → step 0 + rebase CI
- Failing/pending substantive checks → fix and re-run cascade
- `CONFLICTING` → rebase and fix conflicts first

**Agent obligations under `/ship-it`:**

1. **Classify each repo** with § Repo bypass allowlist detection before Step 7; record `BYPASS_ALLOWED` in the report.
2. **Merge all that CAN merge** — tooling/side-project repos (cascade step 2), or any PR that already has required approvals (cascade step 1).
3. **Allowlist:** run the **full cascade** on every green, mergeable, `REVIEW_REQUIRED`-only session PR — never stop after the first `--admin` failure.
4. **Deny-list enterprise:** normal merge only; do **not** attempt bypass; report `REVIEW_REQUIRED` with PR URLs.
5. When every allowed step returns review-required: **do not ask "should I merge?"** — ship-it is standing approval. Surface **one** clear action: **"Need teammate approval on PRs #X, #Y, #Z"** with links (or file `avoid-human-blocked-actions` when a different human UI is required).
6. **Continue in the same session** — process every session PR; rebase review-blocked PRs onto latest base; fix CI regressions.
7. **Report `Merged N/M`** with the delivery report template above. Run Steps 12–13 for repos that merged; list review-pending PRs separately.

## Approval scope (detail)

### Minsky full delivery access

`minsky` (`~/apps/tooling/minsky`) has the same **full delivery access** under `/ship-it` as `dotfiles` and `agentbrew`. Minsky is **not push-blocked** for ship-it — agents have full git push, PR, CI watch, and admin/bypass merge access to minsky remotes (any configured remote **and** `fyodoriv/minsky` on github.com). Cross-repo delivery to minsky is pre-approved: push feature branches, open/update PRs, watch CI, admin merge when green checks pass but review/base-branch policy blocks normal merge, reconcile local `main`, run `minsky install-daemon` after merge, and watch semantic-release (Step 11).


## Approval scope

Approved without another prompt for current-task and allowlisted scope:
- finish incomplete pending changes already in scope
- in any repository explicitly named by the active request, publish normal
  feature-branch updates, create/update the PR, watch/fix CI, and rebase work
  verified as user-owned or current-session onto its actual PR base
- enumerate and ship all user-owned/current-session work in approved repo families, one repo at a time, even when those repos are siblings of the initial workspace
- inspect every local worktree for the current repo or approved repo family, salvage useful current-session/user-owned work before cleanup, and remove only worktrees proven clean, merged, redundant, or superseded after preservation evidence is recorded
- run formatters, linters, tests, builds, and local verification
- create or switch to a short-lived feature branch if needed
- convert clean local-only commits on the default/canonical branch into a short-lived PR branch instead of pushing the default branch directly
- stage explicit files, commit, push the feature branch
- retry `git push` / `gh` egress with unrestricted Shell permissions when Cursor `beforeShellExecution` hooks block delivery (`Pushing source code to this remote has to be done manually`); `/ship-it` pre-approves push to explicitly named current-task repos and approved approved-family remotes for user-owned/current-session branches — never delegate push to the user
- create or update a PR
- watch CI/checks, diagnose failures, push fixes
- when multiple PRs/branches contain the same intended changes, prefer the PR
  that already has human review history, comments, or approvals; move the newer
  branch content onto that reviewed PR and close/supersede the duplicate only
  after the reviewed PR is open and contains the full intended changes, unless
  the user explicitly says to prefer a different PR; duplicate PR closure must
  follow the shared cleanup rule: closing comment with reason + replacement
  links and head-branch deletion unless a documented exception applies
- rewrite a verified user-owned/current-session PR branch in the current repo,
  an explicitly named current-task repo, or an approved-family repo when needed
  to make the PR green/up-to-date: preserve the old remote head, verify PR/head
  ownership, update with `git rebase origin/<base>` or an equivalent
  non-interactive branch reconstruction, re-run required gates, then publish
  with an explicit `git push --force-with-lease=<ref>:<old-oid>` scoped to that
  PR branch. Rebasing owned work is always approved under `/ship-it`.
- merge the PR after required checks pass and repo rules allow it
- in approved repo families, use admin/bypass merge as a required delivery step for a PR authored by the user or owned by this session's agent branch when required checks are green, the PR is otherwise mergeable, and normal merge is blocked solely by review/base-branch policy; do not abandon the reviewed PR, start a fresh task branch, or move to another task because of that policy-only blocker
- treat generic "no admin/bypass outside approved repos" rules as confirming, not forbidding, this approved-family carve-out; only a more specific repo-local rule that names the exact repo/PR class as non-bypassable can block this step
- run the repo's documented release step when it is part of the current-repo normal release workflow
- for own-tool release automation only (`agentbrew`, `dotfiles`, `tasks.md`/`tasks-md`, `minsky`), create GitHub Releases, push release tags, trigger repo release workflows, and publish packages when the repo documents those as the normal release path and the required local/CI gates pass
- after delivery in a tooling-family repo, apply the machine's latest recommended
  updates: reconcile/rebuild the canonical tooling checkout per repo docs, run
  the documented update/sync flow (e.g. `agentbrew sync --pull`, which installs
  recommended catalog items by default, or `dotfiles apply`) from a directory
  without a project Agentfile, and confirm clean status

Still not approved:
- plain `git push --force`, protected-branch direct pushes, hook bypasses
- force-pushes or history rewrites outside verified user-owned/current-session
  PR branches, without a preserved old remote head, without an explicit
  `--force-with-lease` expected OID, against someone else's branch, or for
  unrelated history
- dropping or overwriting local-only default-branch commits before they are preserved and either merged or proven redundant
- admin/bypass merge before checks pass, on a non-mergeable PR, outside the current repo or approved repo family boundary, in repos whose exact repo-local rules forbid it, or for blockers other than green-check review/base-branch policy
- admin/bypass merge of someone else's PR or a PR whose author/owner you cannot verify, even if it is in the user's repository, org, or tooling workspace
- deleting unrelated files/branches/worktrees, worktrees with unsalvaged useful work, or other agents' work
- secrets, credentials, package ownership changes, payments, emails, Slack/Jira/GitHub comments or reviews, except for the required closing comment that is part of an explicitly approved PR close/supersession flow
- cross-workspace publishing outside the repo this session started in, except
  explicitly named current-task repos and approved repo-family
  delivery under `/ship-it`
- production deploys or package publishes outside the own-tool release allowlist unless the repo documents them as the normal release step and this invocation explicitly asks for release

If blocked by one of the above, stop with the exact blocker, the exact command you would need, and why no safer path exists.

## 1. Inventory fast

Run independent read-only checks in parallel:
- `git status --short --branch`
- `git diff --stat`
- `git diff`
- `git log -5 --oneline`
- repo-specific task/status command if documented

Identify:
- current branch and default branch
- all local worktrees from `git worktree list --porcelain`, including branch, HEAD, upstream, dirty status, ahead/behind, open PR, and whether the path is inside the approved repo family
- whether uncommitted changes and local-only commits are yours/current-session, repo automation, or unknown
- ahead/behind counts for the current branch against its upstream and the PR branch against its base
- existing PR number, author, head ref, head repository owner, base ref, mergeability, review decision, and current check states when delivering an existing PR
- duplicate/sibling PRs for the same changeset, including human review history
  (`gh pr view <number> --json reviews,comments` or equivalent)
- repo commit/PR/release rules
- required ticket key, if any
- required verification commands

If on the default/protected branch with uncommitted work, create a short-lived branch before committing. If on the default/protected branch with a clean working tree but local-only commits (`ahead N`), treat those commits as pending deliverable work: create a short-lived branch at the current HEAD, rebase or update that branch onto the fetched upstream default when needed, push it, open/update a PR, watch checks, and merge by the normal repo path. Do not push the default/protected branch directly. If the local-only commits are not clearly current-session work, repo automation (for example `sync: auto-update`), or explicitly requested pending work, stop and report the commit list instead of publishing someone else's work.

If there are duplicate PRs or competing branches for the same changeset, do not
pick the newer/cleaner PR by default. Prefer the PR that already has human
review history, comments, or approvals, even if those reviews are currently
dismissed by a rebase or force-push. Move the newer branch's intended content
onto the reviewed PR's head branch, preserve the reviewed PR URL/thread, and
only close/supersede the duplicate after verifying the reviewed PR is open and
contains the full intended changes. When closing/superseding the duplicate, use
the shared cleanup rule: leave a reasoned closing comment with replacement links
when available and delete the head branch unless a documented exception applies.
Override this only when the user explicitly says to prefer a different PR, the
reviewed PR cannot be reopened after trying the branch-state restoration path,
or the reviewed PR belongs to someone else and ownership/safety rules block
updating it.

If local worktrees exist for the current repo or approved repo family, do not
treat cleanup as a separate optional chore. Before removing any worktree:

1. Inventory every worktree with `git worktree list --porcelain`, then run
   read-only status/diff/log checks in each worktree.
2. Classify each worktree as one of:
   - **ship** — dirty files, local-only commits, or an open branch/PR contains
     useful current-session/user-owned work not represented on the default
     branch or a reviewed PR;
   - **already represented** — `git cherry -v <default> <branch>` or a tree
     diff proves the local commits/diff are already present upstream or in the
     PR that won the duplicate-resolution rule;
   - **unknown/owned elsewhere** — author, branch owner, dirty files, or PR
     ownership cannot be proven current-session/user-owned.
3. For **ship** worktrees, move the useful diff/commits onto the winning
   branch/PR or a new short-lived branch, then run Steps 2–8 before cleanup.
4. For **already represented** worktrees, record the proof in the final report
   (commit OIDs, `git cherry` output, PR/merge URL, or tree-diff result) and
   create a rescue ref/patch only when there is any non-redundant local state.
5. For **unknown/owned elsewhere** worktrees, do not remove them. Report the
   exact blocker and the read-only evidence.
6. After all useful work is shipped or proven redundant, remove only clean or
   redundant current-session worktrees with `git worktree remove <path>` and
   delete their local branches only when merged/redundant and not protected by
   an open PR. This cleanup is pre-approved by `/ship-it` for approved repo
   families after the evidence above; do not ask again.

If updating an existing user-owned/current-session PR branch in the current
repo, an explicitly named current-task repo, or an approved repo-family repo,
and the branch is behind, diverged, or must be rebuilt to remove stale commits,
`/ship-it` approves the rewrite path only after preserving the old remote head:

1. Fetch the base and PR head.
2. Save the old remote OID with `git rev-parse origin/<headRefName>` and create a backup ref such as `git branch backup/pr-<number>-before-ship-it-<timestamp> origin/<headRefName>`.
3. Verify ownership with `gh pr view <number> --json author,headRepositoryOwner,headRefName`.
4. Rebase the PR branch onto `origin/<baseRefName>` or reconstruct it from `origin/<baseRefName>` by cherry-picking only the intended current-session/user-owned commits.
5. Verify locally.
6. Push with an explicit lease, for example `git push --force-with-lease=<headRefName>:<old-remote-oid> origin HEAD:<headRefName>`.

If a required ticket key is missing, infer it from branch name, task file, Jira links, or commit history; ask only if the repo's hooks require a real ticket and none can be found.

## 2. Finish pending work

Complete the requested/pending changes before delivery. Fix obvious failing tests or lint errors caused by the pending changes. Do not expand scope or refactor unrelated code.

For frontend/UI design, build, redesign, or audit work, invoke `hallmark` before emitting UI changes and run the repo's browser/page-error gate when required.

## 3. Verify

Run the fastest relevant verification first, then the repo-required pre-commit/pre-PR suite. Use actual output as evidence. If CI-specific failures are likely, reproduce locally before pushing another fix.

For Jenkins failures, read the actual console log before retrying or pushing fixes.

## 4. Commit

Stage explicit files only. Never use `git add -A`, `git add .`, or `git add -u`.

Use the repo's commit convention. Prefer a concise conventional-commit subject; include the required ticket key when the repo requires one. Do not commit secrets, screenshots for PR evidence, transient logs, or unrelated agent work.

## 5. Push and open/update PR

Push the feature branch to the current repo remote. Use a normal push for new branches or fast-forward updates. If Step 1 authorized a current, explicitly named current-task, or approved-family PR branch rewrite, publish the rewritten branch with explicit `--force-with-lease` and the saved old remote OID; never use plain `--force`.

### Push delivery when Cursor hooks block `git push`

Cursor's managed `git-push-guard` hook (`beforeShellExecution`) can reject agent Shell `git push` / `gh` egress with:

> Pushing source code to this remote has to be done manually.

That hook rejection is **not** a ship-it stop condition for verified
user-owned/current-session work in the current repo, explicitly named
current-task repos, or approved repo families. Agents MUST execute
push/PR/merge themselves — **never** end `/ship-it` with "run these push
commands yourself" or "push from a terminal outside Cursor."

**Retry ladder** (exhaust every step before reporting a hard blocker):

1. Normal push from the repo checkout: `git push -u origin <branch>` (or the repo's documented remote/ref).
2. Retry the same push via Shell with **unrestricted permissions** (`required_permissions: ["all"]` when the tool supports it). This bypasses Cursor's sandboxed hook path while still honoring git hooks and the dotfiles `git`/`gh` wrappers.
3. Retry via a login-shell subprocess with explicit repo context and non-interactive git:
   ```bash
   REPO="/absolute/path/to/checkout"   # required when workspace root is a parent (e.g. ~/apps/tooling)
   BRANCH="$(git -C "$REPO" branch --show-current)"
   /bin/bash -lc "cd \"$REPO\" && GIT_TERMINAL_PROMPT=0 git push -u origin HEAD:${BRANCH}"
   ```
   Run with unrestricted permissions. Prefer explicit `origin` + branch name; use `git -C "$REPO"` when cwd is unreliable.
4. For `gh pr create` / other `gh` egress blocked by the same hook message, retry with `GH_HOST=<your-enterprise-github-host>` (match `git remote get-url origin`) and unrestricted permissions. Set `AGENT_PUBLIC_WRITE_APPROVAL` per dotfiles `bin/gh` when cross-repo PR creation requires it.
5. If the hook still denies after steps 1–4, capture evidence (your agent
   push-guard audit log tail, exact command, remote URL/host, hook stderr) and
   try one documented standing-approval path: `/ship-it` session approval
   covers verified user-owned/current-session feature-branch pushes to the
   current repo, explicitly named current-task repos, `~/apps/tooling/**`,
   own repos on `github.com/<owner>/*`, and any extra repo family the org
   overlay declares.
6. **Last resort only:** report the exact blocker with evidence. Do not suggest manual push until steps 1–5 are exhausted.

**Hook context notes:**

- Enterprise GitHub hosts in your hook allowlist should pass when the remote resolves; fail-closed denials often mean cwd/remote resolution failed — fix with explicit `-C` / `origin` / `GH_HOST`. Audit log `could-not-resolve-remote=origin cwd=workspace_roots` means the hook could not find `origin` from the agent workspace parent — always `cd` into the repo checkout (e.g. `~/apps/tooling/dotfiles`) before push/`gh`.
- Pushes of own-tool repos to `github.com` (dotfiles, agentbrew, minsky, tasks.md) are expected under `/ship-it`. Push the feature branch to `origin` with a normal `git push -u origin <branch>`. The global `git-hooks/pre-push` privacy gate still runs. Cursor's `git-push-guard` can block any shell command containing `git push` to github.com; when it does, follow the retry ladder above with unrestricted Shell permissions.
- Dry-run first when verifying: `git push --dry-run -u origin <branch>`.

**Stack PR overlap gate (before push/open):** When delivering a multi-PR skill stack against the same base, each child branch must be a **phase delta**, not a cumulative branch that still contains parent commits. Before `git push` / `gh pr create`:

```bash
# Disjoint parallel only — exit 0 required for [#A, #B]
bash scripts/check-stack-pr-overlap.sh origin/main feat/phase-a feat/phase-b

# Sequential child — rebuild child on base with only prev..child paths, then re-check overlap shrinks
git checkout -B feat/phase-b origin/main
git checkout feat/phase-b-tip -- $(git diff --name-only feat/phase-a feat/phase-b-tip)
git commit -m "feat: phase b only"
```

If overlap is non-zero and phases are sequential, child PR stays **draft** until parent merges; after parent merges, rebase child onto updated `main` and force-push. Never ship a child PR whose Files tab repeats parent-only paths (registry, fixtures, sweep scripts, etc.). See `shared-rules.md` § Phase-delta branches.

Open or update a PR with:
- **PR validation block (IRON LAW)** — three required sections in every PR body:
  - `## Requirements checklist` (or `## What this PR delivers`) — `[x]` for **this PR only**; epic tracking in Jira
  - `## Previous state` — repro steps (bugfix) or path to feature surface (feature)
  - `## Validation steps` — manual verification for **this PR** with exact commands
  **Forbidden in PR bodies:** `Status:` lines (use GitHub draft/ready). Unchecked epic/sibling requirements (use Jira).
  **Forbidden in Jira descriptions (mirror):** lane tables with live statuses, deferral snapshots, "open work by lane (refreshed DATE)" — use status transitions + issue links + dated **comments** instead (`jira` skill § Epic hygiene; `shared-rules.md` § Jira descriptions are durable charter).
  **Stacked skill carve-out:** greenfield skill PR chains may use `## Summary`, `## Delivery plan`, and `## Test plan` instead (see `shared-rules.md` § Stacked skill PR body shape). Hook + `bin/gh` accept either shape.
  **Draft rule:** chain PRs stay draft until merge blockers are merged; only the unblocked head may be `gh pr ready`.
  Template: `agentbrew/skill-plugins/dev/task-command-center/SKILL.md` § PR validation block. Enforced by `gh-pr-body-requires-validation` hook (blocks) + dotfiles `bin/gh` on agent `pr create`.
- why this change is needed (rationale — separate hook + gh wrapper)
- summary bullets
- test plan with exact commands and pass/fail output
- vision/user-story/competitor trace when the repo requires it
- required agent attribution/footer from repo rules

Do not create a draft PR if the goal is immediate merge, unless repo rules require draft-first.

### Jira delivery lifecycle

When exactly one Jira ticket governs current work, update it only after its
GitHub delivery action succeeds. Use the configured Jira MCP's
`get_available_transitions`, then `transition_issue`:

- When the final non-draft PR opens or becomes ready, use the configured Jira
  MCP to discover available transitions and move the ticket to `In Review`.
  If unavailable, use the project's review-equivalent state, such as `Verify`.
- After that final PR merges, discover transitions again and move the ticket to
  `Done`. If unavailable, use the project's terminal state, such as `Closed`
  with the required `resolution: Done`.
- Do not transition for a draft or blocked stack PR, partial delivery,
  ambiguous or unrelated key, or an epic. Do not guess an equivalent state or
  add a Jira comment unless the user asks.
- `/ship-it` and explicitly scoped delivery authorize these linked-ticket
  transitions. Outside that scope, ask for current-session approval.

## 5a. Capture visual proof for every PR

Before handoff or merge, attach visual proof to every PR.

1. List each changed behavior.
2. Capture proof for each behavior:
   - UI: show the changed state in the live browser.
   - API, CLI, library, config, or state: prefer a pasted terminal transcript
     — the command and its real output in a fenced code block. A transcript is
     copyable, diffable, and searchable, so it beats a picture of the same
     text. A terminal image is an equal alternative, never a requirement.
   - Browser calls: show the Network request and its safe response details.
3. Save each image outside the repository. Use `$AGENT_SCREENSHOT_DIR` when it
   is available.
4. Do not commit images, request bodies with secrets, session data, or customer
   data. Redact secrets from a transcript the same way.
5. Open the PR in the browser. Drag and drop the images into the PR
   description. Do not add local image paths or fake image links. A transcript
   is pasted directly, so it needs no upload.
6. Add `## Visual proof` to the description. For each image or transcript,
   state the case, action, expected result, and observed result.
7. A screenshot of a dashboard does not prove a state change or a network call.
   Capture the relevant request or output too.

### Never stage a terminal image with GUI automation

**Never drive AppleScript, keystrokes, or window activation** to bring a
terminal forward and photograph it. That steals focus from the user's apps and
can type into whatever is frontmost — a chat window, an editor, a browser.

A terminal already prints its output where the agent can read it, so a
transcript costs nothing and proves more. Reach for `screencapture` only when
the user explicitly asks for a terminal image, and even then never pair it with
synthetic keystrokes.

If a rule elsewhere seems to demand an image for non-UI work, this section
wins: paste the transcript and move on.

This rule applies to every PR. A docs-only change still needs proof, such as a
rendered preview or a terminal validation result. "Visual" means legible
evidence a reviewer can check, not necessarily an image. If policy, authentication, or
the environment blocks safe proof, record the exact blocker and keep the PR
unready.

## 6. Watch CI and fix

Run `gh pr checks --watch` or the repo's documented CI watcher. If any check fails, inspect the failing log, fix root cause, verify locally, commit, push, and watch again. Repeat until checks pass or a hard external blocker remains.

**Slow E2E automation checks are non-blocking.** Checks whose names match `*e2e*` or `*automation*` are often slow and flaky by design. Never wait for them, never treat their failure or pending state as a `/ship-it` blocker, and never fix code to make them pass unless the user explicitly asks. Proceed to Step 7 (Merge) when substantive checks pass: lint, unit tests, typecheck, security/Wiz/semgrep, build, and Jenkins `pr-head` build.

## 7. Merge

Run **§ Repo bypass allowlist** detection first. When required checks are green and repo rules allow merge, merge the PR using the repo's normal merge method and delete the branch when safe. If normal merge is blocked, capture the exact merge blocker, then:

1. If auto-merge is available and satisfies the user's "ship it" goal, enable it (allowlist repos only when `REVIEW_REQUIRED` is the only blocker).
2. When `BYPASS_ALLOWED=true` and admin/bypass is appropriate, use the **bypass merge cascade** (§ above) **only when** all of these are true:
   - this is a current-repo PR inside the session workspace boundary, or a PR in an approved repo family covered by this session's `/ship-it` approval;
   - the PR author/head branch owner is you or the agent-created branch for this session's work; verify with `gh pr view --json author,headRepositoryOwner,headRefName` before merging;
   - every required check is green and no security/status check is pending or failing;
   - GitHub reports the PR is otherwise mergeable;
   - the only blocker is `REVIEW_REQUIRED` or base-branch protection policy after green checks.
3. In **allowlist repos** (`~/apps/tooling/**`, own repos on GitHub.com, own-tool names, overlay-declared families), when every condition above is true, the full bypass cascade is the **required** completion path. Do **not** abandon user-owned/current-session PRs solely because normal merge is blocked by review policy.
4. In every allowlist repo: run the **full bypass cascade** when conditions are met — **never stop** after the first `gh pr merge --admin` failure (`At least 1 approving review is required`). When every cascade step fails, report `Merged N/M`, list pending-review PRs with URLs, continue rebase/CI on blocked PRs, and surface teammate approval as the one human action. Do **not** report delivery complete.
5. When `BYPASS_ALLOWED=false` (non-allowlist repo): **do not** run `--admin`, self-approve, or GraphQL bypass. Normal merge only; report `REVIEW_REQUIRED` and PR URLs; continue other session work.
6. Process **every** session PR in the family inventory before final report — never stop after the first review-gate failure on one PR.
7. If any condition other than an unbypassable review gate is false, report the exact blocker and what was already merged.

## 8. Reconcile local default branch

After a PR merges, reconcile the local default/canonical branch before release checks when the working copy for that branch is clean:

1. Fetch the upstream default branch.
2. If the local default branch is behind-only, fast-forward it with `git pull --ff-only` or `git merge --ff-only @{u}`.
3. If the local default branch is ahead-only, first deliver those local-only commits through a short-lived PR branch as described in Inventory/Fix/PR steps; never push the default branch directly.
4. If the local default branch is diverged because its local-only commits were merged by squash/merge commit, verify the local-only commits are represented in the merged PR or remote tree, create a rescue ref such as `refs/ship-it-preserved/<branch>-<timestamp>` at the old local HEAD, then realign the clean local default branch to upstream with the repo's safe local pointer update (`git reset --keep @{u}` or documented equivalent).
5. If the tree is dirty, conflicts exist, the commits are not proven merged/redundant, or the branch contains unknown other-agent/human work, stop with the exact blocker and the preservation ref/command needed.

This reconciliation is local-only cleanup after successful delivery. It does not permit direct protected-branch pushes, dropping unpreserved commits, or `git reset --hard`.

## 9. Clean up shipped/redundant worktrees

After PR merge and local default-branch reconciliation, run the worktree
inventory again. For every current-repo or approved-family worktree classified
as **already represented** or whose useful work you just shipped:

1. Verify it is clean or only contains ignored/generated trash you created in
   this session; if not clean, return to the worktree-salvage classification.
2. Verify its branch is merged, closed/superseded, or tree-equivalent to the
   default branch or the winning PR branch.
3. Preserve evidence in the final report: worktree path, branch, HEAD, proof
   command/result, and whether the local branch was kept or deleted.
4. Run `git worktree remove <path>` for the verified redundant worktree.
5. Delete the local branch only when no open PR depends on it and it is merged
   or proven redundant. Never delete another human/agent's branch.

This step is part of "done" for approved repo-family `/ship-it` runs: stale
worktrees are not harmless when they make future agents rediscover already
shipped work. Cleanup remains salvage-first; if any useful or unknown work
exists, ship/preserve/report it instead of deleting.

## 11. Release

After merge, determine whether the delivered repo is one of the own-tool release repos:

| Repo | Release intent under `/ship-it` | Normal release path |
|---|---|---|
| `agentbrew` | Yes — `/ship-it` means publish the latest merged package when the repo's release gates pass | Prefer the repo's documented auto-release flow: monitor `.github/workflows/auto-publish.yml` after merge until it creates the `release: vX [skip ci]` version/tag commit, reconcile the canonical checkout, then run `npm run publish-latest` (or the repo-documented replacement) to publish the tagged version. Use `npm run release [patch|minor|major]` only when the repo docs say manual local release is the intended path for this change. |
| `dotfiles` | Yes — `/ship-it` means release the applied dotfiles state | After the PR merges on `github.com/fyodoriv/dotfiles`, run the documented apply path (`dotfiles apply` / `chezmoi apply` through the repo wrapper) and doctor/check command required by the touched files. There is no package publish unless the repo adds one. |
| `tasks.md` / `tasks-md` | Yes — `/ship-it` means create the GitHub Release that triggers npm publish | Follow README "Releasing": compute the next semver from the change, create a `vX.Y.Z` GitHub Release targeting `main` with generated notes (`gh release create vX.Y.Z --generate-notes` or repo replacement), watch `.github/workflows/publish.yml`, verify all four npm packages publish or report the exact workflow failure. Prefer the workflow over local `scripts/publish-all.sh`; manual local publishing is fallback only when the workflow is unavailable and the repo docs allow it. |
| `minsky` | Yes — full ship-it delivery + semantic-release when commit types warrant it | **Delivery**: push/PR/merge to any configured minsky remote (or `fyodoriv/minsky`); admin/bypass merge when green. **After merge**: run `minsky install-daemon` from the reconciled canonical checkout to refresh the launchd plist and daemon wiring. **Release**: follow the semantic-release path in `CHANGELOG.md` — after merging to `main`, watch `.github/workflows/release.yml`. A merged `feat:`, `fix:`, `perf:`, or `BREAKING CHANGE:` commit should produce the tag, GitHub Release, changelog update, and npm publish. If the change is `docs:`, `chore:`, `style:`, `refactor:`, `test:`, `build:`, or `ci:`, report that no release is expected unless the user explicitly asks to force one. For the first publish gate or `minsky-npm-publish-v0-1-0`, follow the repo's current TASKS/README instructions exactly. |

Rules for all release work:

1. Use the repo-owned release workflow/script exactly as documented; do not invent a release process.
2. Reconcile the canonical checkout to the merged default branch before release.
3. Run the repo's required verification before publishing or triggering release automation.
4. If a release workflow is asynchronous, actively monitor it and inspect failing logs before retrying or reporting.
5. Verify the published artifact through the authoritative surface the repo documents (workflow conclusion, tag/release existence, npm package version, or deployed local command version).
6. If credentials, npm ownership, Trusted Publisher setup, OTP, or a protected UI confirmation blocks release, stop with the exact blocker and the exact command/UI step needed.
7. For any repo not in the own-tool allowlist, keep the previous behavior: run documented release only when the user explicitly asked for release in this session; otherwise monitor automated release-on-merge if one exists or report "merged; no documented release step found" with evidence searched.

## 12. Apply latest recommended updates (tooling repos)

After delivery completes in an approved tooling-family repo (`~/apps/tooling/**`), **the agent makes the machine run what was just merged** — via Shell, not by telling the operator to run commands later.

### Agent execution mandatory (Steps 12–13)

**Every `/ship-it` run MUST execute Steps 12–13 via Shell.** Documenting the commands without running them is a ship-it failure. The delivery report MUST include command output as proof (especially CDP curl checks and reload exit codes).

When the machine serves a CLI from a canonical checkout (for example the dotfiles `agentbrew` shim), run the repo-documented build (e.g. `npm run build`) before sync so the installed CLI serves merged code. If that checkout is on another branch or carries uncommitted/unknown work, leave it untouched and report it as the blocker.

Ensure `HOME` points at the operator home and `DOTFILES_DIR` resolves to the canonical dotfiles checkout (typically `~/apps/tooling/dotfiles`). Never run apply from `/tmp` or a worktree without setting `HOME` explicitly.

**Chezmoi lock:** If `dotfiles apply` blocks on a stale chezmoi lock, the agent waits briefly, removes the stale lock when safe, and retries — do not abort ship-it and tell the user to apply manually.

### Enable local runtime prerequisites (Step 12 — before sync)

After `git pull` and before `agentbrew sync`, ensure optional **token measurement** tools exist so `agentbrew measure context` can populate static + runtime planes (agentbrew #1322 OpenUsage, ccusage, tokscale). Install attempts are **graceful and non-blocking** — missing Homebrew or failed installs must not abort ship-it; record skip reasons in the delivery report.

| Tool | When to install | Install / check |
|---|---|---|
| **openusage** | `openusage` not on PATH | `brew install janekbaraniewski/tap/openusage` |
| **ccusage** | no permanent install required | `agentbrew measure context` invokes `bunx ccusage …` then `npx -y ccusage …`; optional sanity check: `npx -y ccusage claude daily --json \| head` |
| **tokscale** | no permanent install required | Upstream ships on npm only (no Homebrew tap). `agentbrew measure context` runs it via bunx/npx; manual use: `npx -y tokscale@latest` |

**Tokscale Cursor plane** (optional, may need human browser SSO):

```bash
tokscale cursor login    # browser SSO — if blocked, file avoid-human-blocked-actions doc; do NOT block entire ship-it
tokscale cursor sync     # refresh local Cursor usage cache after login
```

When `tokscale cursor login` lands on SSO, **background** per `sso-browser-isolation` and continue Steps 12–13; document skip reason if login cannot complete this session. Runtime tokscale rows in `agentbrew measure context` may show skipped — that is acceptable when login is pending.

**Agentbrew build after pull:** when this session delivered `agentbrew`, reconcile the canonical checkout and run `npm run build` there **before** `agentbrew sync --pull` so the dotfiles shim serves merged CLI code (including `measure context`).

### Step 12–13 command block (agent runs ALL, in order)

Run this entire block after every tooling-family delivery. Substitute the canonical branch name when it differs from `feat/chezmoi`. Run it from operator `HOME`.

There are two checkouts. `DOTFILES_DIR` is the development checkout on the canonical branch; you edit and push feature branches there. `DOTFILES_APPLIED` is chezmoi's source (`chezmoi source-path`); every apply runs from it. Never run `dotfiles apply` or `chezmoi apply --source` from the development checkout: that relinks `$HOME` to it, and the chezmoi source guard refuses it.

```bash
# Step 12–13 — agents run ALL of these, in order, from operator HOME
export DOTFILES_DIR=~/apps/tooling/dotfiles         # development checkout (canonical branch)
DOTFILES_APPLIED="$(chezmoi source-path)"            # applied checkout (chezmoi's source)
cd "$DOTFILES_DIR" && git pull --ff-only origin feat/chezmoi   # or repo canonical branch
"$DOTFILES_APPLIED/bin/dotfiles-sync"                # fast-forward the applied checkout and re-apply chezmoi

# Optional token runtime tools (graceful — || true when brew unavailable)
command -v openusage >/dev/null || brew install janekbaraniewski/tap/openusage 2>/dev/null || true
# ccusage, tokscale: no brew step — measure context runs them via bunx/npx

cd ~ && "$DOTFILES_APPLIED/bin/dotfiles" apply
cd "$DOTFILES_DIR" && bin/dotfiles-reload-launchagents           # NOT --kickstart unless plist unchanged + process wedged only
# If bootstrap still fails after PR #256 auto-retry, agent MUST run:
# bin/dotfiles-reload-launchagents --kill-chrome
# Then verify CDP:
curl -sf --max-time 2 http://127.0.0.1:9223/json/version && echo CDP9223=ok
curl -sf --max-time 2 http://127.0.0.1:9224/json/version && echo CDP9224=ok
curl -sf --max-time 2 http://127.0.0.1:9225/json/version && echo CDP9225=ok

# When agentbrew was delivered this session — build before sync:
cd ~/apps/tooling/agentbrew && git pull --ff-only origin main 2>/dev/null || true
cd ~/apps/tooling/agentbrew && npm run build                   # skip only when agentbrew not delivered

cd ~ && agentbrew sync --pull && agentbrew status --ci || agentbrew status --fix

# Post-delivery context budget — static + runtime planes (openusage/ccusage/tokscale)
agentbrew measure context

dotfiles doctor --module security --module cursor --module terminal --module agent-browser --module chrome --module resilience --fix
bin/dotfiles-heal-stuck-agents --fix --quiet
# When minsky delivered:
cd ~/apps/tooling/minsky && minsky install-daemon
```

Skip conditional lines only when the condition is false (no minsky delivery → skip `minsky install-daemon`; agentbrew not delivered → skip `npm run build` in agentbrew checkout). Never skip apply, reload, CDP verify, agentbrew sync, `agentbrew measure context`, or doctor for dotfiles/tooling delivery.

`--module chrome` reasserts ChromeWork as the system default browser (Slack/Outlook/Mail link routing) via `chromework-install` when LaunchServices has drifted back to raw Chrome.

This step is part of "done" for tooling delivery — merged-but-not-applied tooling work leaves the machine running stale config.

## 13. Post-delivery verification loop (tooling repos)

After Steps 8–12, the agent runs the machine wrap-up that proves merged dotfiles/agentbrew
state is live — not just merged on GitHub. Repeat this loop until owned doctor
checks pass or a hard external blocker is documented.

### Anti-patterns (forbidden)

- **NEVER** end ship-it with "run these commands yourself" for Steps 12–13
- **NEVER** skip `bin/dotfiles-reload-launchagents` because "plists look unchanged" or "docs-only PR"
- **NEVER** use `--kickstart` as the default reload when bootstrap is the correct mode — `--kickstart` only when the agent is already loaded, the plist on disk is unchanged, and the job is wedged (not when bootstrap failed or plists were just deployed)
- **NEVER** abort on chezmoi lock and delegate apply to the user — wait, clear stale lock, retry
- **NEVER** treat Step 12–13 as documentation-only — agents execute via Shell and attach output evidence
- **NEVER** report "Ship-it complete" or "Delivery complete" when session PRs remain open pending `required_pull_request_reviews` — use **`Merged N/M`** and list pending PR URLs (see **Delivery report honesty**)
- **NEVER** stop `/ship-it` after the first review-gate failure without trying all merge APIs on every green PR and continuing rebase/CI on review-blocked PRs in the same session

### Bootstrap failure ladder (agent runs automatically)

When `bin/dotfiles-reload-launchagents` reports bootstrap failure for CDP Chrome or `com.dotfiles.dotfiles-doctor`:

1. **First pass:** `bin/dotfiles-reload-launchagents` — the script auto-retries failed bootstraps (PR #256).
2. **CDP still down:** `bin/dotfiles-reload-launchagents --kill-chrome`, then reload again.
3. **Verify CDP:** curl ports 9223, 9224, 9225 (see command block above).
4. **Still down:** capture `launchctl bootstrap` / `launchctl print` stderr for the failing label; if the reload script has a gap, fix in dotfiles and re-ship — do not tell the user to reload manually.
5. **Wedged but plist unchanged:** only then use `bin/dotfiles-reload-launchagents --kickstart` (lighter restart without full bootout/bootstrap).

### Apply and reload LaunchAgents (mandatory)

**Every `/ship-it` run that delivers dotfiles or tooling repos MUST execute the command block in Step 12** — merged plist changes are inert until chezmoi deploys them and launchd reloads the agents.

**Order:** reconcile checkout → enable optional token tools → apply (deploy plists) → reload LaunchAgents → verify CDP ports → agentbrew build (when agentbrew shipped) → agentbrew sync → `agentbrew measure context` → doctor → heal-stuck-agents → conditional minsky.

The reload helper bootouts then bootstraps these labels (in order):

- `com.dotfiles.gui-path` — `launchctl setenv PATH` for GUI apps and agents
- `com.dotfiles.network-resilience` — DNS/connectivity after sleep
- `com.dotfiles.heal-stuck-agents` — stuck git SSH + sandbox shell heal (30 min)
- `com.dotfiles.agent-keepawake` — process-scoped `caffeinate -ims` and owned
  Amphetamine protection while Cursor or Claude Code runs on AC or battery ≥20%
- `com.dotfiles.cursor-at-login`
- `com.dotfiles.dotfiles-doctor`
- `com.dotfiles.chrome-profile` — hourly Work profile + ChromeWork default-browser heal
- `com.dotfiles.agent-browser-chrome`, `com.dotfiles.debug-chrome`,
  `com.dotfiles.tooling-chrome` (CDP ports 9223–9225)

### Sync agentbrew from home (not /tmp)

Included in the Step 12 command block. Run from `~` (or any directory **without** a project `Agentfile.yaml`) so git and PATH resolve correctly. If the delivered repo is `agentbrew` itself, rebuild the canonical checkout (`npm run build`) before sync.

### Context budget verification (`agentbrew measure context`)

Included in the Step 12 command block **after** sync. Captures static context-budget metrics plus optional runtime planes:

- **ccusage** — Claude Code daily JSON via bunx/npx
- **openusage** — multi-provider daily rollup when `openusage` is on PATH
- **tokscale** — Cursor IDE today when tokscale is installed and `tokscale cursor login` completed

Record pass/skip lines from command output in the delivery report (`runtime.openusage`, `runtime.ccusage`, `runtime.tokscale` availability). Skipped runtime tools are **non-blocking** when install/login was attempted or brew/SSO unavailable.

**Token playbook reminder (post-measure — mandatory in delivery report):** Read `static.softTokenHeadroom` and `alerts` in `latest.json`. **Agents MUST proactively tell the user to start a new Cursor chat** in every ship-it delivery report after Step 12 sync — stale threads do not load updated rules/MCP/skills. When headroom is low or this delivery changed rules/MCP/skills, cite **`cursor-token-playbook`** / **`context-budget`** and quote headroom numbers. Human mirror: `docs/cursor-token-playbook.md`; shared-rules **## Chat lifecycle**.

### Doctor and owned-check verification

Included in the Step 12 command block. Capture pass/fail counts per module. macOS notification banners stay **off** unless `DOTFILES_DOCTOR_NOTIFY=1` — exit codes and terminal output are the gate.

**Session-fix verification commands** (agent runs after apply; records output as evidence):

```bash
command -v jq python3 python3.13   # must NOT be /usr/bin/*
which -a jq python3 python3.13     # first hits must be dotfiles/bin or ~/.local/bin
codesign -dv "$(readlink -f "$(command -v python3.13)" 2>/dev/null || command -v python3.13)" 2>&1 | grep -E 'Signature=adhoc|TeamIdentifier=not set'
launchctl getenv UV_PYTHON_PREFERENCE   # expect only-managed when set
curl -sf --max-time 2 http://127.0.0.1:9223/json/version >/dev/null && echo CDP9223=ok
curl -sf --max-time 2 http://127.0.0.1:9224/json/version >/dev/null && echo CDP9224=ok
curl -sf --max-time 2 http://127.0.0.1:9225/json/version >/dev/null && echo CDP9225=ok
```

Also confirm Cursor agent/editor parity (default model, extensions, login item)
via the `cursor` doctor module — re-run `--fix` when it auto-repairs drift.

### Minsky daemon refresh (minsky delivery)

When minsky (or dotfiles changes that affect minsky launchd wiring) was delivered:

```bash
cd ~/apps/tooling/minsky && git pull --ff-only origin main
minsky install-daemon
launchctl print "gui/$(id -u)/com.minsky.daemon" 2>/dev/null | grep -E 'path|PATH|ProgramArguments' || true
```

**Minsky-specific verification** (run after `install-daemon`; record output):

```bash
# Tick loop must NOT use /usr/bin/python3 (endpoint policy)
grep -r '/usr/bin/python3' ~/.minsky 2>/dev/null && echo FAIL || echo python3-shim=ok
# launchctl PATH should include dotfiles/bin and ~/.local/bin ahead of /usr/bin
launchctl getenv PATH
# Daemon plist should reference merged minsky checkout
plutil -p ~/Library/LaunchAgents/com.minsky.daemon.plist 2>/dev/null | head -20
```

Re-run `minsky install-daemon` if PATH or python3 shim drift is detected.

### Fix-and-re-ship loop

When doctor reports **fixable** dotfiles-owned failures (stale Chrome logs, unsigned
uv python, PATH shim drift, cursor model parity, agent-browser session wiring):

1. Fix in the dotfiles repo (or agentbrew when the failure is agentbrew-owned).
2. Verify locally (`make test` / targeted bats / doctor re-run).
3. Re-enter Steps 4–12 for that fix PR.
4. Re-run this Step 13 loop.

Stop the loop when all owned checks are green.

### Non-blocking / pre-existing env failures

Document and **do not block** delivery on failures outside dotfiles/agentbrew
ownership, for example:

- VS Code / WebStorm not installed (jetbrains doctor advisory)
- GPG commit signing not configured when the team does not require it
- Endpoint-security exceptions still pending for third-party tools that hardcode
  `/usr/bin/curl`
- Minsky framework-python probe failures — file a `TASKS.md` entry or an
  org-specific overlay note when out of scope for the current PR

Report these separately from owned pass/fail counts so the operator knows what
remains environmental vs what `/ship-it` fixed.

## 14. Memory sync (every delivery, all repo families)

Unlike Steps 12–13, this step is **not tooling-only**. It runs at the end of
every `/ship-it`, in any repo, because session memory is written wherever the
work happened.

Claude Code writes durable memories as markdown under
`~/.claude/projects/<project-slug>/memory/`, one file per fact. Those stores are
project-scoped — they load only when you work in that repo. The shared memory
MCP holds the cross-project semantic index. The managed bridge below keeps the
two in step so a fact learned in one repo is searchable from every other.

```bash
dotfiles-memory-sync-projects
```

This stable dotfiles entry point forwards to `agentbrew memory sync-projects`.
AgentBrew owns the session-aware Streamable HTTP client and the non-content
sync evidence, so this does not create a second raw MCP transport.
Ingestion is idempotent: the daemon rejects exact-match and semantically
duplicate chunks, so a run that finds nothing new stores nothing. Re-running
is always safe.

**Non-blocking.** The script exits 0 even when the daemon is unreachable, and
reports which stores were skipped. Memory infrastructure must never hold up a
delivery. Record any skip in the delivery report alongside other environmental
findings; do not retry in a loop and do not treat it as a delivery failure.

**A daily LaunchAgent covers the rest.**
`com.dotfiles.memory-sync-projects` runs the same script at 05:30 so memory
written during ordinary non-delivery sessions is indexed without waiting for
the next ship-it. AgentBrew also schedules a debounced, non-blocking Claude
Code `SessionEnd` sync. The ship-it call is the explicit delivery path, not
the only path.

**When memory was written this session**, say so in the delivery report with
the store and file count, so the operator can see what was captured rather than
having to go looking for it.

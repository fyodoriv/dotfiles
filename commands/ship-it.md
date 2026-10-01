---
description: Auto-ship owned session work; rebases and guarded pushes pre-approved.
---

# Ship It

## Session activation

If the user has invoked `/ship-it` earlier in this conversation/session, approval remains active for the rest of the conversation/session until the user explicitly disables ship-it mode with **stop ship-it**, **no push**, **plan only**, **read only**, **no commit**, or a narrower scoped limit. Subagents inherit it.

## Planning requests

When the active request asks to create or revise an implementation, architecture,
state-integration, or cross-platform plan, read `writing-plans` before
authoring. For plans spanning a docs hub, hosts, repositories, Jira, or shared
state, also read `task-command-center` →
`references/implementation-plan-template.md`.

Those skills define the required plan shape — goal and rationale first,
material alternatives compared, source-backed facts separated from proposals, a
numbered task series, and the versioned `HostBootstrapPayload` contract for a
host integration. Follow them rather than restating the shape here.

This applies only to a planning request. It does not add a planning stop before
an explicitly requested implementation or delivery.

## Session auto-ship (default)

**verify → commit → push/PR → CI → merge when allowed → Steps 12–13.** Do not ask “ready to commit?”, “should I push?”, or tell the user to run delivery commands. Scoped `/ship-it fix …` still ships that scope end-to-end.

### Push early, let CI verify (IRON LAW)

**While the PR has no review, push every commit as soon as it is committed.** CI
is the verification loop. A local build, test suite, or browser run is not a gate
that must go green first.

- Never hold a commit back for a local check. Commit, push, keep fixing — the
  next push carries the fix. Red CI on an unreviewed PR costs nothing.
- "Half finished" is not a reason to hold back. If it is committed, push it.
- Push after every commit, not once per batch. Long local iteration on unpushed
  commits is the failure mode this rule prevents.
- Never go quiet on delivery. If a push has not happened, say so and why before
  the user asks.

**Once the PR has a review or review comment**, stop pushing silently: a
reviewer is reading a moving target. Batch changes and say what is coming.

## PR description refresh

After final verification and CI evidence are known, but before each PR is merged
or handed off, update its description to reflect the delivered state. Start with
`## Summary` and two or three plain-language sentences that explain why the PR
is needed and what it delivers; follow immediately with `## Details` bullets.
Put validation, rollout, checklist, and repository-required sections after that
opening. Remove stale draft claims and do not replace the summary with a file
inventory or CI-status checklist.

## Visual proof for every PR

Prove every changed behavior before handoff or merge.

- UI: the changed state in a live browser, plus Network details when a browser
  call is the proof. A dashboard screen proves neither.
- Non-UI: a pasted terminal transcript — command and real output in a fenced
  block. It beats a picture of the same text. An image is an equal
  alternative, never a requirement.
- Never drive AppleScript, keystrokes, or window activation to stage a terminal
  image. It steals focus and can type into whatever is frontmost.
- Keep images out of the repo, under `$AGENT_SCREENSHOT_DIR`.
  Never commit proof images. Drag and drop the images into the PR description.
- Add `## Visual proof` naming each case, action, expected and observed result.
- If safe proof is blocked, record the blocker and do not claim ready.

## Owned work: rebase and publication approval

For any repository explicitly named by the active request, `/ship-it` pre-approves normal feature-branch pushes, PR create/update, CI watch/fix, and rebasing work verified as user-owned or current-session:

- Fetch the actual PR base, preserve the old remote head, rebase onto `origin/<base>`, resolve conflicts, and re-run required gates. Rebasing owned work is always approved.
- Publish rewritten owned PR branches only with an explicit `--force-with-lease=<ref>:<old-oid>`. Never use plain `--force`.
- Never bypass a “Pushing source code … manually” guard; see **Push unblock**.
- Verify PR author, head owner, and branch before rewriting. Never rewrite someone else’s branch.

This does not permit admin/bypass merge or release in product repos; the allowlist below and repo-local rules govern those.

## Approved repo families

Broad sibling-repo inventory, auto-merge/bypass, release, cleanup, and machine-refresh scope across approved repo families is limited to:

- tooling repos whose real path is under `~/apps/tooling/**`
- own repos on `github.com/<owner>/*` (minsky, own tools)
- extra families the org overlay declares (`SHIP_IT_EXTRA_REPO_FAMILIES`, colon-separated path globs)

Other product repos are eligible only when explicitly named by the active request, and only for normal delivery plus the owned-work rebase authorization above. They are not added to the bypass/release allowlist.

Own-tool release automation is explicitly enabled for `agentbrew`, `dotfiles`, `tasks.md` / `tasks-md`, and `minsky`.

## Safety and merge boundaries

- Inventory first; salvage useful work from local worktrees before deleting anything.
- On duplicate PRs, prefer reviewed PR on duplicates and preserve its discussion/history.
- **Bypass allow:** tooling, own GitHub.com repos, and overlay families; only after green checks, verified ownership, and mergeability.
- **Bypass deny:** every other product repo; normal merge only, then report `REVIEW_REQUIRED` with URLs.
- **Dangerous — stop and report:** plain `--force`, unleased rewrites, protected pushes, hook bypasses, bypass before green, someone else's PR, non-allowlist bypass, unsalvaged deletion, secrets, unapproved production deploy, or human UI/OTP.
- **Dangerous blocker output:** the category, exact blocked action, safer paths tried, and shipped/remaining status.

**Jira:** After final non-draft PR open/ready, move linked ticket to review; after merge, done. Keep live status in transitions/comments, not descriptions.

## Push unblock

If Cursor's `git-push-guard` rejects an approved current-task or approved-family push because the workspace root is not the git checkout, retry from the absolute checkout:

```bash
REPO="/absolute/path/to/repo"
BRANCH="$(git -C "$REPO" branch --show-current)"
/bin/bash -lc "cd \"$REPO\" && GIT_TERMINAL_PROMPT=0 git push -u origin HEAD:${BRANCH}"
```

Use the same explicit `cd "$REPO"` and enterprise `GH_HOST` context for `gh pr create` or `gh pr merge`. If it still denies, do not evade it: give the operator one command per repo that pushes, opens the PR, watches checks, and merges.

## Memory sync (every delivery, all repos)

Before completion, run `dotfiles-memory-sync-projects` in **every** repo family. It forwards to `agentbrew memory sync-projects`, which indexes `~/.claude/projects/*/memory/` in the managed shared MCP. Facts then are searchable from every primary agent.

It exits 0 even when the daemon is down, reporting skipped stores. **Never block or retry a delivery on it** — record a skip with other environmental findings. When this session wrote memory, name the store and file count in the report.

## Delivery procedure

Follow `~/apps/tooling/dotfiles/docs/ship-it-reference.md` Steps 1–14. Run tooling Steps 12–13 via Shell (`dotfiles apply`, LaunchAgent reload/CDP checks, `agentbrew sync --pull`, context measurement, doctor), then Step 14 (memory sync) on every delivery, whatever the repo family. Report **Merged N/M PRs**, never “complete” while session PRs remain open, and remind the user to start a new chat after config sync.

<!-- turbo -->

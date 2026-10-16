# Decision: keep the update-tooling skill local

- **Task**: replace-relocate-update-tooling-orchestration
- **Date**: 2026-10-16
- **Status**: decided — keep in dotfiles; no relocation now

## Question

Can a maintained upstream tool own more of `skills/update-tooling/SKILL.md`?
The skill does four things:

1. Fast-forward clean primary checkouts under `~/apps/tooling`. Skip and
   report dirty, diverged, ahead, or off-branch checkouts.
2. Refresh the chezmoi applied checkout and reapply it.
3. Run `agentbrew sync --pull` and the machine health checks.
4. Rank the next tasks without editing any queue.

## Options and evidence

| Option | What it covers | Why it does not replace the skill |
|---|---|---|
| topgrade `git_repos` step (topgrade 17.12.3 is installed) | Pulls a list of repos. | `dot_config/topgrade.toml` disables it on purpose: it pulls every repo, including in-flight feature branches. It does not skip and report dirty or diverged checkouts. |
| `chezmoi update` | Pulls and applies the chezmoi source. | `chezmoi help update`: it runs `git pull --autostash --rebase` by default. The skill needs fast-forward only and must never stash someone else's work. It covers step 2 only. |
| myrepos (`mr`), gita, mu-repo | Run one git command over many repos. | None is installed. Each runs the same pull in every repo. None has a "fast-forward only when clean and on the canonical branch, else report" rule. They would need the same wrapper logic the skill already has. |
| Move the skill to agentbrew | — | The skill drives the dotfiles applied checkout, `dotfiles apply`, and `com.dotfiles.*` LaunchAgents. dotfiles owns those (AGENTS.md ownership boundary). agentbrew owns only its own sync step, which the skill already calls (`agentbrew sync --pull`). |

## Recommendation

Keep the skill in dotfiles. Its local-only reason: the safety rule
("fast-forward only a clean checkout on its canonical branch; otherwise
fetch and report") plus the applied-checkout step have no upstream
equivalent. The upstream tools above either pull everything or rebase with
autostash.

Re-check when one of these lands upstream:

- topgrade gains a per-repo "skip when dirty or diverged" option for `git_repos`.
- chezmoi `update` gains a fast-forward-only mode without autostash.

No follow-up task: nothing to build now.

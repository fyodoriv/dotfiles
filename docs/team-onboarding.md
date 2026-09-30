# Team Rollout Guide

How to roll out dotfiles to your team. Covers strategy, communication, and support.

> **Individual setup?** See [onboarding.md](onboarding.md). Enterprise users should also follow their organization's overlay onboarding doc.
>
> **AI agents?** See [agentbrew-setup.md](agentbrew-setup.md) for MCP credentials, generated config ownership, and sync recovery before rolling AI tooling out to a team.
>
> **Enterprise team lead?** If your organization keeps a private dotfiles overlay (e.g. `dotfiles-<org>`), use its team-adoption playbook for pilot sizing, GHE, VPN, MDM, support-channel guidance, and rollout health checks.
>
> Every section below applies to any team. Items labeled "enterprise" are opt-in — leave `is_enterprise: false` (the default) and the enterprise modules become silent no-ops; the rest of the rollout (pilot → team core → optional full) is identical.

---

## Rollout strategy

Start small and expand. Don't push `full` profile on day one.

| Phase | Timeline | What happens |
|-------|----------|--------------|
| **Pilot** | Week 1 | 2-3 volunteers install with `core` profile. They find rough edges. |
| **Team core** | Week 2-3 | Announce to the full team. Everyone installs `core`. |
| **Optional full** | Week 4+ | Power users opt into `full` profile at their own pace. |
| **Enterprise** | Anytime | Enterprise users enable enterprise mode (see your organization's overlay onboarding doc). |

### Why `core` first

The `core` profile includes the git, macos, ssh, tools, workflow, sync, and security modules plus a curated set of brew packages. It's opinionated about things most developers agree on (fast key repeat, hidden files visible, no Dock animation) but doesn't touch shell config, IDE configs, AI tools, or macOS visual preferences.

The `full` profile adds more modules (cursor, claude, jetbrains, extras, etc.) and additional Homebrew packages beyond `core`. It's great for power users but can surprise people who aren't expecting it — compare profiles in [onboarding.md#profiles](onboarding.md#profiles) or run `make count` for live totals.


---

## Customizing the fork for your team

Before announcing, fork the repo and adjust defaults:

1. **Pick your profile default** -- edit `.chezmoi.yaml.tmpl` to set `profile: core` or `full`
2. **Set enterprise defaults** -- if your company uses GitHub Enterprise, update the domain prompts
3. **Remove modules you don't need** -- see [forking-guide.md#removing-modules-you-dont-need](forking-guide.md#removing-modules-you-dont-need) for the dependency matrix
4. **Add team-specific brew packages** -- edit the Brewfile in `.chezmoiscripts/run_onchange_brew.sh.tmpl`
5. **Test on a fresh account** -- `chezmoi init --source ~/apps/dotfiles --apply` should work in under 15 minutes on a clean macOS

See [forking-guide.md](forking-guide.md) for the full customization guide and checklist.

---

## Team lead checklist

Run through this before announcing to the team:

- [ ] Fork the repo (or clone to your team's GitHub org)
- [ ] Customize `.chezmoi.yaml.tmpl` defaults for your team
- [ ] Remove or disable modules your team doesn't need
- [ ] Test the install on a fresh macOS account or VM
- [ ] Run `dotfiles doctor --fix` and confirm all checks pass
- [ ] Run `dotfiles validate --quick` during customization for fast checks of hardcoded user paths in shared config, enterprise hostnames, secrets, tracked `.env` files, and script hygiene
- [ ] Run full `dotfiles validate` before announcing the fork; it includes lint and the full bats suite, so it replaces a separate `make check`
- [ ] If your organization ships a private overlay, complete its pilot gate before announcing
- [ ] If the team will use AI tooling, validate [agentbrew setup and recovery](agentbrew-setup.md) on one pilot machine
- [ ] Write your Slack announcement (see template below)
- [ ] Set up a Slack channel or thread for support during rollout
- [ ] Schedule a 15-minute walkthrough for the team (optional but helps)
- [ ] After week 1, run a quick survey: "Did it work? What broke?"

---

## Pre-announcement validation gate

Use `dotfiles validate` as the final gate before you share a fork URL with the
team. It checks shared config (`home/`, `git-hooks/`, `Agentfile.yaml`, and
other deployed files) for hardcoded user paths, enterprise hostnames, leaked secrets,
tracked `.env` files, non-executable scripts, missing shebangs, and
world-writable scripts, then runs lint and the full bats suite. Use
`dotfiles validate --quick` for fast iterations while customizing the fork;
`--quick` skips lint and tests, so it should not be the final
pre-announcement gate.

---

## 5-minute quick-start for team members

Share this with your team. It's the minimum viable install:

```bash
# 1. Clone the team fork
git clone git@github.com:YOUR-ORG/dotfiles.git ~/apps/dotfiles

# 2. Run the installer
chezmoi init --source ~/apps/dotfiles --apply

# 3. Answer the prompts (defaults are fine for most people)

# 4. Verify everything works
dotfiles doctor --fix

# 5. Open a new terminal tab to pick up the changes
```

That's it. The installer handles brew packages, macOS defaults, symlinks, and LaunchAgents.

**Keep your personal config**: `~/.zshrc.local` and `~/.gitconfig.local` are never overwritten. Put your personal aliases, PATH additions, and git identity there.

**Optional AI tooling**: If your team enables `use_ai_tools: true`, run
`agentbrew init`, `agentbrew setup`, `agentbrew sync --agentfile
~/apps/dotfiles/Agentfile.yaml`, and `agentbrew status` after the dotfiles
install. The full flow is in [agentbrew-setup.md](agentbrew-setup.md).

---

## Sample Slack announcement

Copy and customize:

> **New: team dotfiles repo**
>
> We've set up a shared dotfiles repo to standardize our dev environments. It handles:
> - macOS defaults (fast key repeat, Finder shows hidden files, no Dock animation)
> - Shell config (zsh with fast startup, git aliases, completions)
> - Brew packages (the tools we all use, installed automatically)
> - Self-healing health checks (`dotfiles doctor --fix` finds and repairs drift)
>
> **Setup takes ~10 minutes.** Follow the guide: [link to your fork's onboarding.md]
>
> This won't break your personal config. Your `~/.zshrc.local` and `~/.gitconfig.local` are untouched.
>
> We're starting with the `core` profile (git, macOS defaults, SSH, tools, workflow, sync, security). Power users can opt into `full` later.
>
> Questions? Drop them in #your-dotfiles-channel.

---

## FAQ for common pushback

**"Will this break my machine?"**
No. The installer uses chezmoi's safe merge strategy. Your personal files (`~/.zshrc.local`, `~/.gitconfig.local`) are never touched. macOS defaults are all reversible. If something feels wrong, run `dotfiles doctor` to diagnose, or see [onboarding.md#troubleshooting](onboarding.md#troubleshooting) for full rollback steps.

**"Can I keep my own aliases and shell config?"**
Yes. Put them in `~/.zshrc.local` -- it's sourced at the end of `.zshrc` and is gitignored. Same for `~/.gitconfig.local`.

**"I already have a dotfiles setup."**
The installer won't clobber your existing files if they differ. Chezmoi shows a diff and asks before overwriting. You can migrate gradually -- start with `core` profile and add modules as you get comfortable.

**"What if I don't want some of the macOS defaults?"**
The `core` profile applies fewer defaults than `full`. Check [onboarding.md#profiles](onboarding.md#profiles) for exactly what each profile changes. You can also remove individual modules from the fork.

**"Do I need to be on the Virtual Private Network / have enterprise access?"**
Only if your team enables enterprise mode (GitHub Enterprise, org-specific tools shipped via the overlay). The `core` profile works entirely offline after the initial brew install.

**"How do I update when the repo changes?"**
Run `dotfiles apply` (or just open a new terminal -- the sync LaunchAgent does it automatically). Updates are incremental -- only changed files are applied.

**"What if something goes wrong?"**
Run `dotfiles doctor --fix` first -- it auto-repairs most issues. If that doesn't help, check [onboarding.md#troubleshooting](onboarding.md#troubleshooting) or ask in the team channel.

---

## Measuring success

Track these during rollout:

| Metric | How to measure | Target |
|--------|---------------|--------|
| Adoption rate | Count forks / clones (see below) | 80% in 2 weeks |
| Setup time | Ask in survey or time the walkthrough | Under 15 minutes |
| Doctor pass rate | Aggregate `dotfiles doctor --report` output | 95% of runs at 0 failures |
| Support requests | Count messages in dotfiles channel | Decreasing week over week |

### Counting adoption (forks and clones)

If your team fork is on GitHub, use the API to count forks:

```bash
# Replace YOUR-ORG/dotfiles with your team fork
gh api repos/YOUR-ORG/dotfiles -q '.forks_count'
```

For clone-based adoption (no forking), count unique contributors who have committed:

```bash
git log --format='%ae' | sort -u | wc -l
```

Or ask GitHub for traffic (requires push access):

```bash
gh api repos/YOUR-ORG/dotfiles/traffic/clones -q '.uniques'
```

### Measuring doctor pass rate

Each team member can generate a markdown report and share it:

```bash
dotfiles doctor --report
```

To collect pass rates across the team, have each member run:

```bash
dotfiles doctor --quiet
# Output: ✓ 130 passed  ⊘ 5 skipped    (exit code 0 = healthy)
# Output: ✓ 125  ✗ 5  ⊘ 5              (exit code 1 = issues)
```

The exit code tells you whether the machine is healthy:

```bash
dotfiles doctor --quiet && echo "PASS" || echo "FAIL"
```

To aggregate across a team, have each member post their one-liner output to Slack, or collect reports into a shared folder:

```bash
# Generate a timestamped report file
dotfiles doctor --report > "doctor-report-$(whoami)-$(date +%Y%m%d).md"
```

### Tracking doctor trends over time

Each `dotfiles doctor` run is logged to `~/.dotfiles-stats.jsonl`. Team members can view their personal trend:

```bash
dotfiles doctor --trends
```

This shows the last 12 runs with pass/fail/fixed counts. A healthy machine shows zero failures across all runs.

### Measuring time saved

The stats dashboard shows how much time automation has saved:

```bash
dotfiles stats
```

This tracks runs of sync, doctor, cleanup, git-maintain, and morning scripts. Share the one-liner version in standups:

```bash
dotfiles stats --oneliner
```

### Quick team health script

Run this on each team member's machine (or have them run it) to get a one-line health summary:

```bash
printf "%-20s " "$(whoami)" && dotfiles doctor --quiet
```

Collect these into a Slack thread during rollout weeks to spot who needs help.

---

## Upgrading from core to full

Team members who want more can upgrade anytime:

```bash
# Re-run chezmoi init and select "full" at the profile prompt
chezmoi init --source ~/apps/dotfiles --apply
# Answer "full" when asked for profile
```

This adds the remaining modules. Run `dotfiles doctor --fix` after to ensure everything is configured.

---

## Maintaining your fork

After the initial rollout, you'll need to keep your fork in sync with upstream changes.

### Recommended merge strategy

Use **rebase** for a clean history:

```bash
# Add upstream remote (one-time)
git remote add upstream git@github.com:ORIGINAL-OWNER/dotfiles.git

# Sync with upstream
git fetch upstream
git rebase upstream/main
```

If you prefer **merge** (preserves fork-specific history):

```bash
git fetch upstream
git merge upstream/main
```

### Resolving conflicts

The most common conflict is in `.chezmoi.yaml.tmpl` where you've changed defaults for your org. When a conflict occurs:

```bash
# Keep YOUR version of .chezmoi.yaml.tmpl (your org's defaults matter)
git checkout --ours .chezmoi.yaml.tmpl
git add .chezmoi.yaml.tmpl
git rebase --continue
```

For Brewfile conflicts in `.chezmoiscripts/run_onchange_brew.sh.tmpl`, manually merge to keep both upstream packages and your team's additions.

### When to diverge vs stay in sync

| Scenario | Recommendation |
|----------|---------------|
| New upstream module you don't need | Stay in sync — ignore it via `.chezmoiignore` |
| Upstream changes macOS defaults | Merge — review the diff, keep what you agree with |
| Your team needs custom modules | Diverge — add your own `modules/<name>/doctor.sh` |
| Upstream Brewfile adds a package | Merge — use `brew_skip` config to exclude unwanted packages |

### Recommended sync cadence

- **Monthly**: fetch upstream and merge/rebase. Review changelog for breaking changes.
- **After upstream releases**: check the release notes, merge if relevant.
- **Immediately**: if upstream fixes a security issue in `bin/dotfiles-audit` or SSH config.

---

## Links

- [Individual onboarding](onboarding.md) -- full step-by-step setup
- Your organization's overlay onboarding doc -- enterprise mode, GHE, secrets (org-specific)
- [Forking guide](forking-guide.md) -- customization, module removal, team checklist
- [Architecture](architecture.md) -- how the pieces fit together
- [Module reference](module-reference.md) -- what each doctor module checks

# Adoption Checklist for Team Leads

A step-by-step checklist for rolling out this dotfiles repo to your team. Each step links to detailed documentation.

> Every step below works for any team. Items tagged "enterprise" only apply when
> you flip `is_enterprise: true` (GitHub Enterprise clones, MDM-aware power
> management, internal service URLs). Leave `is_enterprise: false` and the
> enterprise modules become silent no-ops; the rest of the checklist is
> identical for any company.
>
> If your organization keeps a private dotfiles overlay (e.g. `dotfiles-<org>`),
> consult its playbook for pilot sizing, GHE bootstrap, VPN/MDM caveats, and
> support-channel guidance before announcing the rollout.

## Prerequisites

- [ ] macOS 13+ (Ventura or later)
- [ ] Git and Xcode Command Line Tools installed (`xcode-select --install`)
- [ ] Admin access to create a fork (if using GitHub Enterprise)
- [ ] Decision: fork or clone? See [Forking guide](forking-guide.md) for trade-offs

## 1. Fork and customize

- [ ] Fork the repo (or clone if using as-is)
- [ ] Review and remove personal preferences: see [Forking guide: removing modules](forking-guide.md#removing-modules-you-dont-need)
- [ ] Set default chezmoi config values for your team in `.chezmoi.yaml.tmpl`
- [ ] Choose a default profile (`core` or `full`) — see [Profiles](../CONTRIBUTING.md#profiles)

## 2. Configure enterprise settings (optional — only if `is_enterprise: true`)

- [ ] Set `is_enterprise: true` default if your team needs enterprise tools
- [ ] Update `home/zshenv.secrets.example` with your company's service URLs
- [ ] Review `macos.sh` power management settings for MDM compatibility (see your overlay's MDM notes)
- [ ] Review [Security model](security-model.md) for trust boundaries and `sudo` usage

## 3. Test the install

- [ ] Do a clean install on a test machine (or VM)
- [ ] Run `chezmoi init --source ~/apps/dotfiles --apply`
- [ ] Run `dotfiles doctor --fix` and verify zero failures
- [ ] Open a fresh terminal — confirm shell loads in <200ms

## 4. Write team-specific docs

- [ ] Update README quick start with your fork URL
- [ ] Add team-specific onboarding notes (for example, VPN requirements and SSH key setup)
- [ ] Document any checks your team should skip: `dotfiles doctor --skip <check-id>`
- [ ] Run `dotfiles validate --quick` while iterating on docs or config changes for a fast pre-share safety check; quick mode reports that TASKS.md lint, shellcheck, and tests were skipped
- [ ] Run full `dotfiles validate` before announcing the fork — full validation includes hardcoded-path checks across shared config, enterprise-hostname checks, secret scans, tracked `.env` checks, script hygiene, TASKS.md lint, shellcheck, and the bats suite
- [ ] If your overlay ships its own validate scripts (via `EXTRA_VALIDATE_DIR`), run them too before announcing the fork

## 5. Roll out to the team

- [ ] Share the fork URL and onboarding guide
- [ ] Each team member runs the [Installation](../README.md#installation) steps
- [ ] Each member verifies with `dotfiles doctor`
- [ ] Point members to [Troubleshooting](troubleshooting.md) for common issues

## 6. Ongoing maintenance

- [ ] Enable `auto_upgrade: true` for teams that want automatic tool updates
- [ ] Review the [CI setup guide](ci-setup.md) for branch protection and automated checks
- [ ] Periodically pull upstream changes if you forked (see [Forking guide: further reading](forking-guide.md#further-reading))

## Related docs

- [Onboarding guide](onboarding.md) — full setup walkthrough for individuals
- [Forking guide](forking-guide.md) — what to keep, remove, and customize
- [Security model](security-model.md) — trust boundaries, secrets, encryption
- [FAQ](../README.md#faq) — common questions and answers

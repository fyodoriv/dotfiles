# User Story: Add Your organization's Config Without Forking Dotfiles

> Your company has internal tools, brewfile entries, doctor checks, or shell env that don't belong in the public dotfiles repo. Drop them in a private `<base>-<company>` overlay repo and point dotfiles at it. Symmetric uninstall when you're done.

**Metric:** Public forks of dotfiles — see [docs/metrics.md](../metrics.md#metrics).

**Tests:** tests/e2e/stories-e2e.bats, tests/overlay-root-doctor.bats, tests/overlay-root-uninstall.bats.

This story is the **overlay** path. It's different from the [forking guide](../forking-guide.md), which describes forking the whole dotfiles repo to change defaults org-wide. Use this one when you want to **keep dotfiles as-is** (so you get future updates for free) and just plug in a tiny company-specific layer.

## Recommended: a company plugin

The current contract is a signed, pinned plugin: see [plugins.md](../plugins.md).

```bash
export DOTFILES_PLUGINS_V2=1
dotfiles plugin new <company>            # scaffold dotfiles-<company>/
# push it, then release an SSH-signed tag: git tag -s v1.0.0 -m v1.0.0
dotfiles plugin add <git-url>@v1.0.0 --signer "$(cat release-key.pub)"
dotfiles apply
dotfiles plugin remove <company>         # symmetric uninstall
```

The rest of this page describes the legacy v1 overlay. It still works until
the next major version; convert one with `dotfiles plugin migrate <dir>`.

## When to use this vs forking

| You want… | Use this overlay story | Use the [forking guide](../forking-guide.md) |
|-----------|------------------------|-----------------------------------------------|
| One or two company-specific brew packages | ✅ | overkill |
| A company-specific doctor check | ✅ | overkill |
| Organization-specific shell env vars (auth tokens, proxy URLs) | ✅ | overkill |
| Different default for `profile` / `is_enterprise` org-wide | — | ✅ |
| Replace large parts of `home/zshrc` | — | ✅ |
| Maintain your own permanent fork with org-specific releases | — | ✅ |

Overlay = additive. Fork = divergent.

## Worked example

An org overlay is a separate repo (for example `dotfiles-<org>`) that carries everything org-specific: its own `Agentfile.yaml`, encrypted enterprise SSH config, security-agent settings (`DOTFILES_MANAGED_ENDPOINT`, `DOTFILES_ENDPOINT_AGENT_APPS`), and private-reference patterns (`oss-readiness.env`). The base repo stays generic.

## Steps

```bash
# 1. Make sure you have dotfiles installed (the public base)
git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles
chezmoi init --source ~/apps/dotfiles --apply

# 2. Create a private repo for your company-specific overlay
gh repo create <your-handle>/dotfiles-<company> --private
git clone git@github.com:<your-handle>/dotfiles-<company>.git ~/apps/dotfiles-<company>

# 3. Drop content into the overlay (see "Overlay layout" below)
mkdir -p ~/apps/dotfiles-<company>/{modules,validate,brewfile}
# … add your company-specific files …

# 4. Tell chezmoi where the overlay lives
chezmoi edit-config
# add: extra_overlay_root: ~/apps/dotfiles-<company>

# 5. Apply — dotfiles loads the overlay you named (no auto-discovery)
dotfiles apply
```

## Overlay layout

Your overlay repo follows the same directory conventions as dotfiles. The base repo discovers each subdirectory via documented extension hooks:

```
dotfiles-<company>/
├── modules/<name>/doctor.sh        Auto-discovered by `dotfiles-doctor`
├── validate/<name>.sh              Auto-discovered by `dotfiles-validate`
├── brewfile/Brewfile               Inlined into the brew-install lifecycle script
├── home/zshrc.<company>            Not loaded by v1 overlays; use a v2 plugin `contributes.shell`
├── vscode/settings.json            Merged into VS Code generated settings by vscode doctor
├── Agentfile.yaml                  Merged into the canonical global Agentfile
└── README.md                       Lists what your overlay contributes
```

Each subdirectory is independently optional — ship only what you need.

Use `vscode/settings.json` for org-only editor keys (for example
`github-enterprise.uri` pointing at your GitHub Enterprise host, or an internal MCP command).
Do not put employer hostnames in the base `dotfiles` repo — keep them in the overlay.

## What dotfiles does with your overlay

After `dotfiles apply` runs with `extra_overlay_root` set:

1. **`dotfiles doctor`** — runs every `modules/<name>/doctor.sh` from the overlay alongside the base modules. Output is interleaved.
2. **`dotfiles validate`** — runs every `validate/<name>.sh` from the overlay alongside base validates.
3. **Brewfile** — your overlay's `brewfile/Brewfile` lines are appended to the brew-install lifecycle script (so `dotfiles apply` installs both base packages and your company-specific ones).
4. **Shell env** — an `EXTRA_OVERLAY_ROOT` overlay has no shell hook. A v2 plugin (`DOTFILES_PLUGINS_V2=1`) with `capabilities.shell_fragment: true` sets `contributes.shell`, and `~/.zshrc` loads it before `~/.zshrc.local` ([plugin-system.md](../plugin-system.md)).
5. **Agentfile** — your overlay's `Agentfile.yaml` is merged with the base Agentfile into `~/.config/agentbrew/Agentfile.yaml`; agentbrew syncs once from that canonical file. Older agentbrew releases without `agentfile merge` fall back to syncing the base Agentfile first and the overlay with `--no-prune`.
6. **Editor settings** — when present, `vscode/settings.json` is deep-merged into the editor's generated settings by the vscode doctor module (so org-only keys survive `doctor --fix`).

**One overlay at a time.** `extra_overlay_root` is a single path, not a list. If you need to combine multiple overlays, merge them into one repo or fork the whole dotfiles base.

## Symmetric uninstall

When the overlay isn't needed anymore (job change, project ended, simplifying setup):

```bash
# 1. Remove the chezmoi data key
chezmoi edit-config
# delete the `extra_overlay_root:` line

# 2. Re-apply — base dotfiles state restored, overlay contributions gone
dotfiles apply

# 3. (Optional) Delete the overlay clone if you don't need it for reference
rm -rf ~/apps/dotfiles-<company>
```

Reapplying without the overlay restores the base state cleanly. User-added entries (anything you added to `~/.zshrc.local` or similar) survive.

## Verify the overlay is active

```bash
dotfiles doctor
# the overlay's modules appear in the doctor output alongside base modules

echo $EXTRA_OVERLAY_ROOT
# should print your overlay's path
```

If `dotfiles doctor` doesn't show your overlay's checks, run `dotfiles apply` again — the `extra_overlay_root` key may not have made it into the rendered config.

## Why this exists

The base dotfiles repo stays generic enough to be open-source-ready. Organization-specific content (auth tokens, internal hostnames, proprietary tooling configs) has no business in a public repo. The overlay pattern lets you maintain both — public base + private layer — without either touching the other's source. The base repo's [`tests/no-internal-refs.bats`](../../tests/no-internal-refs.bats) test enforces this invariant: any company-specific identifier in the base repo fails the build.

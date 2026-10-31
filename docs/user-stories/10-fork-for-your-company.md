# User Story: Add Your organization's Config Without Forking Dotfiles

**Agent contract:** Claude Code + ChatGPT Work/Codex; shared memory required when configured; regression: tests/user-stories.bats.

Follow the [agent workflow acceptance](README.md#agent-workflow-acceptance) before context-dependent work.

> Your company has internal tools, brewfile entries, doctor checks, or shell env that don't belong in the public dotfiles repo. Put them in a private, signed company plugin and install it with one command. Symmetric uninstall when you're done.

**Metric:** Public forks of dotfiles — see [docs/metrics.md](../metrics.md#metrics).

**Tests:** tests/e2e/stories-e2e.bats, tests/plugin-v2.bats, tests/plugin-extensions.bats, tests/plugin-v1-removed.bats.

This story is the **plugin** path. It's different from the [forking guide](../forking-guide.md), which describes forking the whole dotfiles repo to change defaults org-wide. Use this one when you want to **keep dotfiles as-is** (so you get future updates for free) and add a small company layer. The full contract is in [plugins.md](../plugins.md).

## When to use this vs forking

| You want… | Use a company plugin | Use the [forking guide](../forking-guide.md) |
|-----------|----------------------|-----------------------------------------------|
| One or two company-specific brew packages | ✅ | overkill |
| A company-specific doctor check | ✅ | overkill |
| Organization-specific shell env (proxy URLs; secrets by reference) | ✅ | overkill |
| Different default for `profile` / `is_enterprise` org-wide | — | ✅ |
| Replace large parts of `home/zshrc` | — | ✅ |
| Maintain your own permanent fork with org-specific releases | — | ✅ |

Plugin = additive. Fork = divergent.

## Steps

```bash
# 1. Scaffold the plugin repo
dotfiles plugin new <company>            # creates dotfiles-<company>/

# 2. Add content (see docs/plugins.md "Manifest"), push it to a private repo,
#    then release an SSH-signed annotated tag
git -C dotfiles-<company> tag -s v1.0.0 -m v1.0.0

# 3. Install it pinned and signed; approve the capabilities once
dotfiles plugin add <git-url>@v1.0.0 --signer "$(cat release-key.pub)"

# 4. Apply
dotfiles apply
```

## Verify the plugin is active

```bash
dotfiles plugin list        # state "ok" means it matches plugins.lock
dotfiles doctor             # plugin checks show as <plugin>/<id>
```

A plugin that no longer matches its lock is disabled, and
`plugins.<name>.verified` says why.

## Symmetric uninstall

```bash
dotfiles plugin remove <company>   # unloads its LaunchAgents, deletes the checkout and lock entry
dotfiles apply
```

User-added entries (anything in `~/.zshrc.local` or similar) survive.

## Coming from the v1 overlay

The v1 overlay (`EXTRA_OVERLAY_ROOT` and the other `EXTRA_*` variables, and
the chezmoi key `extra_overlay_root`) was removed. A leftover setting stops
`dotfiles doctor`, `validate`, and `apply` with one line that names it.
Convert the overlay on the machine that has it:

```bash
dotfiles plugin migrate ~/apps/dotfiles-<company>   # writes dotfiles-plugin.yaml.draft, lists unmapped files
# review the draft, rename it to dotfiles-plugin.yaml, commit, sign a tag, then:
dotfiles plugin add <git-url>@<tag> --signer "<key>"
```

Then remove `EXTRA_OVERLAY_ROOT` from your shell profile, and delete
`extra_overlay_root` from `~/.config/chezmoi/chezmoi.yaml`.

## Why this exists

The base dotfiles repo stays generic enough to be open-source-ready. Organization-specific content (internal hostnames, proprietary tooling configs) has no business in a public repo. A pinned, signed plugin lets you maintain both — public base + private layer — without either touching the other's source. The base repo's [`tests/no-internal-refs.bats`](../../tests/no-internal-refs.bats) test enforces this invariant: any company-specific identifier in the base repo fails the build.

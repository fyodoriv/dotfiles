# dotfiles

![shell startup < 200ms](https://img.shields.io/badge/shell_startup-%3C200ms-brightgreen)

macOS developer dotfiles with self-healing health checks. Powered by [chezmoi](https://chezmoi.io).

**Quick start** (from a stock Mac):

```bash
git clone <your-fork-or-origin> ~/apps/dotfiles
chezmoi init --source ~/apps/dotfiles --apply
dotfiles doctor --fix   # verify everything installed correctly
```

**Verify:** after installation, open a fresh terminal and run `dotfiles doctor`. All checks should pass. See [docs/onboarding.md](docs/onboarding.md) for a full setup walkthrough.

> **Enterprise team?** Use the overlay model for organization-specific clone URLs, tools, and internal services. Team leads should start with the adoption playbook.
>
> **Something went wrong?** See [docs/troubleshooting.md](docs/troubleshooting.md) for symptom-first fixes.

### Contents

| Getting started | Using | Extending | Reference |
|---|---|---|---|
| [Installation](#installation) | [Features](#features) | [Fork & customize](docs/forking-guide.md) | [CLI reference](#cli-reference) |
| [Enterprise setup](#enterprise-setup) | [Modules](#modules) | [How it works](#how-it-works) | [Environment variables](#environment-variables) |
| [For other companies](#for-other-companies) | [LaunchAgents](#launchagents) | [Development](#development) | [Repo layout](#repo-layout) |
| [Troubleshooting](#troubleshooting) | [AI agent config](#ai-agent-config) | [Performance](#performance) | [FAQ](#faq) |

## The problem

A new Mac ships with conservative defaults — slow key repeat, Spotlight crawling `node_modules`, NVM adding 300ms to every shell, `git status` doing single-threaded I/O. You fix these manually, then forget what you changed. Six months later you get a new machine and start over. Settings drift. Scripts break. Nobody notices until something is slow again.

**This repo fixes it.** One command deploys macOS defaults, per-module health checks, and LaunchAgents for continuous automation. A weekly doctor catches drift and auto-repairs it.

## Highlights

- **One command setup** — `chezmoi init --source ~/apps/dotfiles --apply` goes from stock macOS to fully configured.
- **Self-healing** — `dotfiles doctor --fix` auto-discovers every module's checks and repairs drift. Only the configured chezmoi source checkout can apply fixes or reload Home LaunchAgents; other checkouts audit without mutating the machine. Runs weekly via LaunchAgent.
- **Durable local agent memory** — one loopback-only `mcp-memory-service`
  daemon serves every agent; `dotfiles memory` provides status, repair,
  transaction-safe backup verification, scheduled maintenance, and an
  on-demand localhost dashboard.
- **Two profiles** — `core` (7 baseline modules, team-friendly) and `full`
  (all 35 discovered modules, subject to feature gates). Selected at init time.
- **149 macOS defaults** applied via lifecycle scripts — key repeat, Spotlight pruning/exclusions, 15-minute idle lock, Finder, animations, analytics, power management. See [notable changes](docs/onboarding.md#step-2-initialize-chezmoi).
- **~30ms shell startup** (200ms CI budget) — fnm replaces NVM, tool inits cached to disk, lazy loading everywhere.
- **bats tests** + shellcheck on every script. `make check` runs them before each commit; see [Where tests run](#where-tests-run).
- **LaunchAgents** — sync, doctor, cleanup, git-maintain, cursor-priority, morning, and more.
- **Time tracking** — `dotfiles stats` shows runs, time saved, and streak.
- **Never destroys personal config** — `~/.zshrc.local` and `~/.gitconfig.local` are gitignored and never overwritten.

## Installation

```bash
chezmoi init --source ~/apps/dotfiles --apply   # prompts for profile: core or full
dotfiles doctor --fix                            # verify and auto-repair
```

That's it. Chezmoi deploys all config files, installs Homebrew packages, applies macOS defaults, loads LaunchAgents, and syncs agent config via agentbrew — all from a single command. The doctor step verifies everything installed correctly and auto-fixes any issues.

> **Prefer a guided setup?** Run `dotfiles quickstart` instead — it checks prerequisites, walks you through chezmoi init, and runs doctor automatically.
>
> **Something not working?** See [docs/troubleshooting.md](docs/troubleshooting.md) for symptom-first entries with causes and fixes.
>
> **On a work machine?** See [Enterprise setup](#enterprise-setup) first — there are extra steps for enterprise tools, GitHub Enterprise SSH, and internal services.
>
> **Multiple Macs?** See [docs/multi-machine.md](docs/multi-machine.md) for syncing dotfiles across machines.

> **What will change?** See [docs/what-gets-changed.md](docs/what-gets-changed.md) for a full inventory of system changes before running apply.

### Configuration

During `chezmoi init`, you'll be prompted for these values. They're stored in `~/.config/chezmoi/chezmoi.yaml` — edit and run `dotfiles apply` to change later.

| Prompt | Variable | Default | What it does |
|--------|----------|---------|-------------|
| Profile | `profile` | `full` | `core` = 7 baseline modules, team-friendly. `full` = all 35 discovered modules, subject to feature gates. |
| Enterprise mode | `is_enterprise` | `false` | Adds generic enterprise tools (AWS CLI, K8s, Gradle, Java 21, enterprise SSH). Organization-specific tools belong in the org overlay repo, not the base repo. |
| AI tooling | `use_ai_tools` | `false` | Deploys `~/.zshrc.ai-tools` with GPT-5.5 XHigh Thinking Fast Devin defaults (`DEVIN_MODEL=gpt-5-5-xhigh-priority`) and Devin CLI aliases — see [`AGENTS.md` § Model Configuration](AGENTS.md#model-configuration) for the default-model policy and [troubleshooting](docs/troubleshooting.md#devin-uses-the-wrong-model) if Devin picks the wrong model |
| Local AI | `use_local_ai` | `false` | Installs the local-LLM fallback stack (`pipx`, `aider-chat`, `huggingface_hub[cli]`, and `mlx-lm` on native Apple Silicon). Local health checks never spawn models; the Ollama supervisor skips startup when another healthy owner already serves `:11434`. The ~30 GB model download still requires the sentinel in [docs/local-llm.md](docs/local-llm.md). |
| Cursor | `use_cursor` | `true` | Manages Cursor: the `cursor` doctor module, the `run_after_cursor-*` scripts, the Cursor-only LaunchAgents (`cursor-at-login`, `heal-stuck-agents`), and agentbrew's Cursor target. `false` turns all of them off, removes those LaunchAgents on the next apply, and merges `config/agentfile-no-cursor.yaml` (`excludeAgents: [cursor]`) into the agentbrew Agentfile. Dotfiles does not uninstall the Cursor app itself. |
| *(not prompted)* | `auto_sync` | `true` | Scheduled `dotfiles-sync` (30 min) and `tooling-sync` (60 min) LaunchAgents. Set `false` in `~/.config/chezmoi/chezmoi.yaml` and run `dotfiles apply` to remove them and sync by hand. |
| *(not prompted)* | `claude_model` / `claude_effort` | `claude-opus-5-5` / `xhigh` | Override the Claude Code model and effort that `dotfiles apply` pins in `~/.claude/settings.json`; Cursor follows it. Use it for an org overlay or one Mac. The `DOTFILES_CLAUDE_MODEL` / `DOTFILES_CLAUDE_EFFORT` env vars win over these keys. See [`AGENTS.md` § Model Configuration](AGENTS.md#model-configuration). |
| Auto-upgrade | `auto_upgrade` | `false` | Weekly Topgrade via LaunchAgent (Sunday 9 AM); managed-endpoint safe mode disables it while a required runtime publisher is blocked. |
| Encryption | `use_encryption` | `false` | age encryption for secrets (requires key at `~/.config/chezmoi/key.txt`) |
| Dotfiles directory | `dotfiles_dir` | `apps/dotfiles` | Path relative to `$HOME` where this repo lives. Leave as default unless you cloned elsewhere. |
| Repos directory | `repos_dir` | `apps` | Path relative to `$HOME` where your code repos live. Used by `git-maintain` and doctor. |
| Git work name | `git_work_name` | _(empty)_ | Commit author name for your work/default identity |
| Git work email | `git_work_email` | `your.username@<work_email_domain>` (enterprise) | Commit email for your work/default identity |
| Split git identity | `git_personal_enabled` | `false` | Enable a separate personal identity for any `github.com` remote. Work identity stays default for enterprise remotes. |
| Git personal name | `git_personal_name` | _(empty, only if split enabled)_ | Commit author name used for `github.com` remotes |
| Git personal email | `git_personal_email` | _(empty, only if split enabled)_ | Commit email for `github.com` remotes — consider `<username>@users.noreply.github.com` for privacy |
| *(not prompted)* | `brew_skip` | `[]` | List of Homebrew package names to skip during install. Edit `~/.config/chezmoi/chezmoi.yaml` directly — see example below. |

Enterprise-only prompts (when `is_enterprise: true`):

| Prompt | Variable | Default | What it does |
|--------|----------|---------|-------------|
| Work email domain | `work_email_domain` | `example.com` | Chrome work profile detection |
| GitHub Enterprise host | `github_enterprise_host` | `github.example.com` | Enterprise SSH and repo checks |

**Skipping Homebrew packages:** If a package can't be installed (VPN restriction, corporate policy, personal preference), add it to `brew_skip` in `~/.config/chezmoi/chezmoi.yaml`:

```yaml
data:
  brew_skip:
    - "watchman"
    - "rancher"
```

Then run `dotfiles apply` — the listed packages will be excluded from `brew bundle`.

### Profile comparison

| | **core** | **full** |
|---|---|---|
| **Modules** | 7 baseline | 35 discovered (feature-gated) |
| **Brew packages** | essentials set (`make count` with `core`) | full profile set (`make count` with `full`) |
| **What's included** | git, macOS defaults, SSH, CLI tools, workflow automation, sync, security | Everything in core + shell config, editor, terminal, prompt, IDE, AI tools, extras |
| **What's NOT included** | Shell customization, IDE config, AI tools, visual tweaks | — |
| **Best for** | Team rollouts, new users, shared machines | Power users, solo machines |

**Which should I choose?** Start with `core` if you're new to the team, evaluating these dotfiles, or deploying across multiple machines — it gives you solid git config, macOS defaults, and automation without changing your shell or editor setup. Choose `full` if you want the complete experience: Ghostty terminal, starship prompt, tmux, AI agent tooling, and all the visual tweaks. You can switch at any time with `dotfiles profile core` or `dotfiles profile full`, then `dotfiles apply`.

### Profile module list

The `core` profile includes 7 baseline modules — the essentials that most
developers agree on. The `full` profile enables all 35 discovered modules;
enterprise, local-AI, browser, and similar modules still apply their own
feature-specific gates.

| Module | Profile | What it checks |
|--------|---------|----------------|
| git | core | gitconfig symlink, local identity, delta pager, performance settings |
| macos | core | Finder, Dock, Spotlight, keyboard, trackpad defaults |
| security | core | SSH key permissions, secrets file, age encryption |
| ssh | core | SSH config, known_hosts, agent forwarding |
| sync | core | Auto-sync LaunchAgent, repo health |
| tools | core | Homebrew packages, CLI tools |
| workflow | core | LaunchAgents loaded, automation health |
| agent-browser | full | Chrome profile for headless browser automation |
| agentbrew | full | Agent config sync health |
| chrome | full | Chrome default profile, work profile detection, ChromeWork URL router |
| claude | full | Claude config, MCP servers, GitHub Enterprise integration |
| cursor | full | Cursor settings, keybindings, extensions |
| devin | full | Devin CLI config — deprecated and frozen; doctor skips it ([AGENTS.md § Deprecated agents](AGENTS.md#deprecated-agents--frozen)) |
| editor | full | editorconfig, global editor settings |
| enterprise | full | AWS CLI, kubectl, Gradle, Java, enterprise SSH |
| extras | full | Fastfetch config, misc tools |
| jetbrains | full | IdeaVim config |
| windsurf | full | Windsurf settings + keybindings + extensions, inherited from WebStorm — deprecated and frozen; doctor skips it |
| local-llm | full | Local-LLM stack detection (pipx, aider, huggingface-cli, mlx-lm) for Minsky's claude-exhaustion fallback |
| memory | full | Shared MCP daemon, maintenance job, schema/embedding health, and backup freshness/integrity |
| prompt | full | Starship config symlink and theme |
| shell | full | zshrc/zshenv symlinks, PATH, tool caches (fnm, fzf, zoxide), history |
| terminal | full | Ghostty config, terminal defaults |
| upgrade | full | Auto-upgrade agent, brew outdated |

Switch profiles at any time: `dotfiles profile core` or `dotfiles profile full`, then `dotfiles apply`.

Full-only prompts (when `profile: full`):

| Prompt | Variable | Default | What it does |
|--------|----------|---------|-------------|
| Morning hour | `morning_hour` | `8` | Hour (0-23) for morning briefing LaunchAgent |
| Morning minute | `morning_minute` | `30` | Minute (0-59) for morning briefing LaunchAgent |

See [docs/forking-guide.md](docs/forking-guide.md) for the full variable reference and how to change defaults for your team.

### Prerequisites

**Required** (prompted automatically if missing):

| Dependency | Notes |
|-----------|-------|
| macOS (Apple Silicon or Intel) | Ventura 13+, Sonoma 14, or Sequoia 15 |
| Xcode Command Line Tools | Auto-prompted; or `xcode-select --install` |
| GitHub access (SSH) | For cloning; GitHub Enterprise users see the [enterprise section](#enterprise-setup) |
| ~10 GB disk space | Homebrew packages, casks, and Xcode CLT |
| `sudo` access | One-time for Homebrew install and `pmset` power settings |

**Auto-installed** (no action needed):

| Dependency | How |
|-----------|-----|
| chezmoi | `brew install chezmoi`, or via the organization one-liner in the overlay repo, which auto-installs it |
| Homebrew | Installed by chezmoi lifecycle script if missing |
| All CLI tools (bat, fd, ripgrep, etc.) | Installed via Homebrew on first `dotfiles apply` |

**Optional** (enable at init time):

| Dependency | When needed |
|-----------|-------------|
| age key (`~/.config/chezmoi/key.txt`) | Only if you select `use_encryption: true` for encrypted secrets |
| Anthropic API key | Only if you select `use_ai_tools: true` for AI agent tooling |
| agentbrew | Only for AI agent MCP/skills sync — installed separately |

### macOS compatibility

| macOS version | Status | Notes |
|--------------|--------|-------|
| Sequoia 15 | Tested | Primary development target. Native tiling settings included. |
| Sonoma 14 | Tested | Fully supported. Window tiling settings ignored (no-op). |
| Ventura 13 | Supported | Minimum version. All core features work. |
| macOS 16+ | Partial | `reduceTransparency` requires manual TCC approval (System Settings > Privacy). Script warns and continues. |

**Architecture**: both Apple Silicon (arm64) and Intel (x86_64) are supported. Homebrew installs to `/opt/homebrew` (arm64) or `/usr/local` (Intel) — the bootstrap script detects this automatically.

**Version-specific caveats**:
- `com.apple.universalaccess reduceTransparency` is TCC-protected on macOS 16+ and cannot be set via `defaults write` — the script warns and skips
- `terminal-notifier` notification banners may show empty on macOS 14+ without notification permissions granted to Script Editor
- Sequoia native window tiling settings (`EnableEdgeTiling`, `EnableTopTiling`) are no-ops on older versions

### Uninstalling

If you decide dotfiles isn't for you, you can cleanly remove everything:

```bash
dotfiles uninstall --dry-run   # preview what will be removed (no changes made)
dotfiles uninstall             # remove for real
```

**What it does:**
1. **Unloads LaunchAgents** — stops and removes all `com.dotfiles.*` scheduled tasks
2. **Removes symlinks** — deletes only symlinks that point back into the dotfiles repo (e.g., `~/.zshrc`, `~/.gitconfig`, `~/.zshenv`)

**What it preserves (never touched):**
- `~/.zshrc.local` — your personal shell customizations
- `~/.gitconfig.local` — your name, email, and signing key
- `~/.zshenv.secrets` — API keys and tokens

**To fully remove the repo after uninstalling:**

```bash
rm -rf ~/apps/dotfiles
```

After uninstalling, macOS defaults (key repeat speed, Dock behavior, etc.) remain as-is — they don't revert automatically. Reset them manually in System Settings if needed.

### Known issues & caveats

| Caveat | Scope | Details |
|--------|-------|---------|
| **Gatekeeper quarantine disabled** | Full profile | `LSQuarantine` is set to `false` — downloaded apps won't show the "are you sure?" dialog. Review `data/macos-defaults.json` (search for `LSQuarantine`) if this concerns you. |
| **TCC-protected defaults on macOS 16+** | All profiles | `com.apple.universalaccess reduceTransparency` cannot be set via `defaults write` — the script warns and skips. Toggle manually in System Settings > Accessibility > Display. |
| **CDP debug ports (9222-9225)** | Full profile | Chrome remote debugging is enabled on localhost for browser automation. Port 9222 is the separate `chrome-debug` profile; ports 9223/9224/9225 are login-started managed Chromes that agents must attach to instead of launching against their profile dirs. They are not `KeepAlive`: closing Chrome for logout/shutdown must stay closed. |
| **VPN/proxy interactions** | Enterprise | Some Homebrew downloads and `curl`-based health checks may time out behind corporate proxy. Disconnect VPN for initial setup if needed. |
| **macOS defaults don't auto-revert** | All profiles | `dotfiles uninstall` removes symlinks and LaunchAgents but does not reset macOS `defaults write` changes. Revert manually in System Settings. |

## For other companies

This repo works for any macOS team. To adopt it at your organization:

1. **Fork the repo** and clone your fork
2. **Edit `.chezmoi.yaml.tmpl`** — change `work_email_domain` and `github_enterprise_host` defaults to your organization
3. **Remove Organization-specific references** — see [docs/forking-guide.md#removing-all-organization-specific-references](docs/forking-guide.md#removing-all-organization-specific-references) for the full list
4. **Customize the Brewfile** — add or remove packages in `.chezmoiscripts/run_onchange_brew.sh.tmpl`
5. **Run `dotfiles doctor`** to verify your customized fork works
6. **Run `dotfiles validate` before sharing** — see the [adoption checklist](docs/adoption-checklist.md#4-write-team-specific-docs) and [team rollout guide](docs/team-onboarding.md#pre-announcement-validation-gate)

Enterprise mode (`is_enterprise: true`) installs generic tools (AWS CLI, K8s, Gradle, Java 21) — useful at any company. Organization-specific packages belong in an overlay repo, not the base repo.

See [docs/forking-guide.md](docs/forking-guide.md) for the full customization guide and team adoption checklist.

## Enterprise setup

[![CI](https://github.example.com/your-org/dotfiles/actions/workflows/ci.yml/badge.svg)](https://github.example.com/your-org/dotfiles/actions/workflows/ci.yml)

If you are joining through a company fork, a few extra steps get you up and running with enterprise tools and internal services. If you are rolling this repo out to a team, start with [docs/team-onboarding.md](docs/team-onboarding.md) before sending the individual setup flow.

> **VPN/proxy note:** Keep the VPN on for the `git clone` step if your GitHub Enterprise host requires it. Disconnect the VPN before running `chezmoi init` if Homebrew downloads time out behind a corporate proxy. Reconnect after setup completes.

**Clone from GitHub Enterprise:**

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --source ~/apps/dotfiles --apply --ssh git@github.example.com:your-org/dotfiles.git
```

### 1. GitHub Enterprise access

Add your SSH key to your GitHub Enterprise host and verify:

```bash
ssh -T git@github.example.com
```

### 2. Enterprise mode

Enterprise mode installs AWS CLI, Kubernetes tools, Gradle, Java 21, and configures enterprise SSH. These are generic tools useful at any company. Organization-specific tools belong in an overlay repo; enabling enterprise mode in the base repo only installs generic enterprise tooling.

```bash
dotfiles enterprise on    # sets is_enterprise: true in chezmoi config + re-applies
dotfiles enterprise off   # disable when not needed
dotfiles enterprise       # show current status
```

Only enable this if your work requires AWS, K8s, or JVM tooling — it adds extra Homebrew packages and SSH config.

### 3. AI tooling (optional)

AI agent tooling (Devin CLI shortcuts, model defaults, agent-browser config) is opt-in. When prompted during `chezmoi init`, set `use_ai_tools: true` — or enable it later by editing `~/.config/chezmoi/chezmoi.yaml` and running `dotfiles apply`.

This deploys `~/.zshrc.ai-tools`, which sets `DEVIN_MODEL` and Devin CLI aliases (`dv`, `dvp`, `dvc`, `dvr`, `dvl`). It also installs a `~/bin/claude` wrapper that strips leaked `ANTHROPIC_MODEL` values and starts Claude Code with `--permission-mode bypassPermissions` unless you pass an explicit permission mode.

Teammates who want MCP servers, shared skills, and generated agent config should also follow [docs/agentbrew-setup.md](docs/agentbrew-setup.md) for `agentbrew init`, credential setup, sync, status checks, and recovery.

If Devin starts with the wrong model, use the symptom-first recovery entry in [docs/troubleshooting.md#devin-uses-the-wrong-model](docs/troubleshooting.md#devin-uses-the-wrong-model) instead of editing generated config by hand.

### 4. Enterprise secrets

Copy the example and fill in your Splunk, Jenkins, and GitHub Enterprise tokens:

```bash
cp ~/apps/dotfiles/home/zshenv.secrets.example ~/.zshenv.secrets
# Edit with your credentials — this file is never tracked in git
```

Or auto-populate MCP server credentials with `agentbrew setup` (or target one server, such as `agentbrew setup atlassian`).

### Full walkthrough

See [docs/onboarding.md](docs/onboarding.md) for the complete onboarding guide including `.gitconfig.local` setup, troubleshooting, and profile selection. On a work machine, also see your org overlay's onboarding guide; team leads should use [docs/team-onboarding.md](docs/team-onboarding.md) to validate a pilot before announcing a rollout.

## Features

### Apply and update

```bash
dotfiles update             # whole-machine update: pull/apply/agentbrew/packages/doctor
dotfiles apply              # deploy all config (chezmoi apply)
dotfiles apply --pull       # narrow path: pull dotfiles source + apply only
dotfiles diff               # preview pending changes without writing
```

Every `dotfiles` command auto-checks for updates (fetches at most once/hour). When behind:
```
⬆ Update available (3 commit(s) behind). Run: dotfiles update
```

### Health checks

Checks are auto-discovered from `modules/*/doctor.sh`. Adding a new module automatically adds its checks — no editing the doctor script.
When an organization overlay is auto-discovered, other checkouts of the base
repository are excluded so their modules do not run twice.

The `workspace` module extends the view beyond this repo: `dotfiles-workspace status` rolls up every declared workspace folder (repos, dirty/ahead state, TASKS.md queue estimates) — see [docs/workspace.md](docs/workspace.md).

```bash
dotfiles doctor              # audit all modules
dotfiles doctor --fix        # auto-repair drift
dotfiles doctor --skip ID    # permanently skip a check
dotfiles doctor --list       # show all check IDs
dotfiles doctor --trends     # show pass/fail/fix trend over time
```

`--skip` validates the ID before editing `.overrides`; run `dotfiles doctor --list`
first to copy the exact check ID.

**What `--fix` does (and doesn't do):** creates missing symlinks, loads LaunchAgents, sets git config defaults, and installs missing Homebrew packages. It **never** deletes files, overwrites personal config (`~/.zshrc.local`, `~/.gitconfig.local`), or runs destructive commands. Safe to run repeatedly.

The Homebrew bottle signature audit keeps its security coverage while avoiding
an expensive `codesign` scan on every healthy doctor run. It caches only a
successful scan for 24 hours. A changed Cellar inventory, a signing repair, or
`DOTFILES_DOCTOR_REFRESH=1 dotfiles doctor` forces a fresh audit. Unsigned and
unverifiable results are never cached.

Doctor initializes its own endpoint-safe PATH, then ignores inherited
non-interactive shell startup hooks so they do not run again for every check.

### Shared agent memory

With the full profile and AI tooling enabled, every agent connects to one
loopback-only `mcp-memory-service` daemon on `127.0.0.1:18765`. AgentBrew owns
the daemon, MCP registration, behavioral bootstrap, backups, and maintenance;
dotfiles owns the declarative `memory.enabled` setting and login ordering.

```bash
agentbrew memory status          # readiness, tool count, identity, database, and backups
agentbrew memory doctor          # full MCP discovery, bootstrap, schema, and backup health
agentbrew memory doctor --ready  # initialize + initialized notification + non-empty tools/list + bootstrap
agentbrew memory transport-report --json # read-only evidence before a transport/auth migration
agentbrew memory fix             # reconcile, wait for discovery readiness, and maintain
agentbrew memory backup          # transaction-safe on-demand SQLite backup
agentbrew memory verify-backup   # integrity-check the newest backup
agentbrew memory dashboard       # open the upstream local browser UI
```

`dotfiles memory ...` remains a compatibility shim to the same AgentBrew
commands; it never starts a second daemon. Dotfiles apply unloads and removes
retired `com.dotfiles.mcp-memory*` agents, while Cursor's login LaunchAgent runs
the AgentBrew repair/doctor gate before opening the IDE. The readiness gate
accepts JSON or SSE MCP responses and requires a non-empty `tools/list`; URL
probe failures remain visible to the AgentBrew heal/snapshot path. If daemon recovery reports
`cursorReloadRecommended`, manually use **Developer: Reload Window** or fully
restart Cursor — there is no supported single-server reconnect command, and
dotfiles never quits Cursor or edits generated `~/.cursor/mcp.json`.

`dotfiles-memory-sync-projects` is also a compatibility shim. It forwards the
daily `com.dotfiles.memory-sync-projects` LaunchAgent and `/ship-it` trigger to
`agentbrew memory sync-projects`, which uses AgentBrew's session-aware MCP
client instead of a second raw HTTP implementation. AgentBrew's Claude Code
`SessionEnd` hook adds a debounced, non-blocking fast path. The daily job
remains recovery when a session hook cannot run. Claude project-memory files
are one source for the same managed store that Cursor, Windsurf, Devin, and
Codex use; they are not a separate backend.
Normal project-memory sync is metadata-delta based. Use
`agentbrew memory sync-projects --force` only for a deliberate recovery
re-ingest. The fast path writes a bounded receipt and retries after a failed
child instead of treating a failed schedule as fresh.
The memory doctor module delegates project-memory freshness and the transport
report to AgentBrew. It never parses Claude memory files or reimplements the
MCP protocol. Global recall remains the default; project provenance tags only
support intentional filtering.
Repository knowledge learned by `/learn-repos`
is accepted as authoritative only when repo path, Git revision, and the
canonical source-document fingerprint all match. See
[`docs/learn-repos-reference.md`](docs/learn-repos-reference.md).

#### Tracking trends

`dotfiles doctor --trends` shows the last 12 runs in a table:

```
📊 Doctor Trend (last 12 runs)

  Date          Pass   Fail  Fixed
  ────────────  ─────  ─────  ─────
  2026-03-25      128      0      0
  2026-04-01      130      2      2
  2026-04-08      132      0      0

  Total doctor runs: 42
```

- **Pass**: checks that passed (green when no failures)
- **Fail**: checks that failed (red when > 0)
- **Fixed**: checks auto-repaired by `--fix`

Data comes from `~/.dotfiles-stats.jsonl` — the same file used by `dotfiles stats`. Each `dotfiles doctor` run appends a record. The weekly LaunchAgent ensures continuous data collection.

### Security audit

```bash
dotfiles audit               # SSH permissions, secrets, git credentials, repo hygiene
dotfiles audit --report      # markdown report
```

Checks: SSH key permissions (600), agent forwarding safety, secret patterns in tracked files, `.env` file detection, sensitive file permissions, git credential helper audit, and root-level stray agent artifacts such as `=5.5.0` pip redirects or absolute Homebrew symlinks. Secret-scan fixtures must use an explicit fixture path or an inline `# dotfiles-secret-allowlist: reason` comment.

**Security model summary:** everything runs as your user — no system-level changes outside `~/`. The only `sudo` calls are `pmset` (power management) and `dscacheutil` (DNS flush), both fail silently if sudo is unavailable. Secrets use age encryption or macOS Keychain, never plaintext in tracked files. See [docs/security-model.md](docs/security-model.md) for the full trust boundary analysis.

**Canonical repo and privacy contract:** `github.com/fyodoriv/dotfiles` is
the canonical home. The canonical branch is `feat/chezmoi`, which is
also the GitHub default branch. Nothing rewrites history.

The normal flow is the same on every machine:

1. Create a short-lived feature branch.
2. Run `git push origin <branch>`.
3. Open a PR on github.com and merge it.
4. Run `git pull` on `feat/chezmoi` to get the latest.

Public history **never** carries a private author email, a configured
private identifier from the overlay-provided scanner, or a hardcoded secret.
Pre-commit and pre-push enforce that contract before a commit leaves the
machine. Nothing rewrites history later, so a private email cannot be made
safe after the fact.

The global `git-hooks/pre-push` applies a privacy gate to pushes of dotfiles,
agentbrew, and every repo in `config/public-push-remotes.txt` to github.com.
It blocks commits whose author or committer email matches the private-email
pattern. It also blocks files changed in the push (read at the pushed commit)
that match the private-identifier pattern, and lists paths only. Each pushed
commit's added lines, file names, and message are checked too; that message
lists commit ids only. Both patterns come from the org
overlay's `oss-readiness.env`, which `lib/oss-readiness.sh` loads. With no
overlay, those two checks have nothing to match. The hook then delegates to
the repo-local `hooks/pre-push`.

The structural deletion guard remains active for `bin/`, `tests/`, `lib/`,
`modules/`, and `skills/`. It has two audited exceptions:

- retiring `lib/dotfiles-memory.sh` while the AgentBrew compatibility shim
  is present.

Scheduled `dotfiles-sync` pushes to the configured remotes (normally only
`origin`). Every push passes the same pre-push gate.
Reporting a leak and the full design live in [SECURITY.md](SECURITY.md).

### Scaffolding

```bash
dotfiles add <file> [--copy] [--module M]       # add a config file
dotfiles unmanage <file>                        # remove a managed file
dotfiles new-module <name> [--severity S]       # create a doctor module
dotfiles brew-add <pkg> [--cask] [--full-only]  # add a Homebrew package
dotfiles defaults-add <domain> <key> <val> <type>  # add a macOS default
dotfiles profile [core|full]                    # show or switch profile
```

### Time tracking

Every automated task records how much manual time it saved:

| Task | Runs via | Per-run estimate | What scales it |
|------|----------|-----------------|----------------|
| `sync` | LaunchAgent (every 30 min) | 3s | — |
| `doctor` | LaunchAgent (weekly) | 2s (flat) | — |
| `cleanup` | LaunchAgent (weekly) | 10s / cache | Number of cache locations cleaned |
| `git-maintain` | LaunchAgent (daily) | 5s / repo | Number of repos in `~/apps` |
| `cursor-priority` | LaunchAgent (every 60s) | 0 (bookkeeping) | — |
| `morning` | Manual (daily) | 15s / repo | Number of repos pulled |

```bash
dotfiles stats               # full dashboard: total, streak, per-task breakdown
dotfiles stats --oneliner    # single line for embedding
dotfiles stats --recalc      # rewrite historical data with current estimates
```

## Modules

Profile selection happens at `chezmoi init` time. Each module provides health checks via `modules/*/doctor.sh`.

### Core (non-opinionated, team-friendly)

| Module | What it does |
|--------|-------------|
| **git** | delta diffs (with fallback), rerere, histogram algorithm, auto-rebase, auto-prune, aliases |
| **macos** | Fastest key repeat, no autocorrect/smart quotes, Finder improvements, Spotlight pruning/exclusions, 15-minute idle lock, analytics off |
| **ssh** | macOS Keychain agent, connection multiplexing, keep-alive |
| **tools** | bat, eza, fd, ripgrep, jq, btop, gum, fastfetch, htop, tealdeer, tree |
| **workflow** | Scripts + LaunchAgents (sync, doctor, cleanup, git-maintain, capslock-control, gui-path) |
| **sync** | Dotfiles auto-sync health: launchagent loaded, recent sync, clean working tree |
| **security** | SSH key permissions, secrets scanning, git credential audit, endpoint-security signing checks |

### Full-only (opinionated — review before installing)

| Module | What it does | Gate |
|--------|-------------|------|
| **shell** | Zsh: 100K history, completion, lazy fnm (0.05s startup), fzf/zoxide, aliases | |
| **editor** | `.editorconfig` (2-space indent, UTF-8, LF) + `.gitignore_global` + `.npmrc` | |
| **jetbrains** | IdeaVim (113 mappings), WebStorm keymap, 8GB heap, zero-latency typing | |
| **windsurf** | Generated local settings.json + keybindings.json symlinked, 25+ extensions, IntelliJ keymap + vim layered, 8GB tsserver, file-watcher exclusions for monorepos, CA bundle for corp TLS inspection | |
| **terminal** | Ghostty (GPU-accelerated, Catppuccin auto light/dark, Nerd Font) + tmux (C-a, vim nav, mouse) | |
| **prompt** | Starship: git branch/status, node/python version, command duration | |
| **extras** | Lazygit, tig, yazi, hyperfine, duf/dust/procs, and other niche CLI tools | |
| **upgrade** | Software upgrade LaunchAgent loaded, last upgrade within 14 days | |
| **claude** | Verifies Google Drive MCP setup (agent config managed by agentbrew) | `enterprise` `ai-tools` |
| **cursor** | Cursor generated local settings.json, keybindings, tasks, Claude Code model parity, agent settings parity (vim/fonts/glass keybindings), and extension bundle with WebStorm Islands Dark colors, Material icons, JetBrainsMono/Ghostty font parity, quick-open/default-branch git shortcuts, performance parity, and log/lockfile search ignores; HTTP(S) links inherit the ChromeWork system default instead of using Cursor's unexpanded external-browser path (MCP/rules managed by agentbrew) | `ai-tools` |
| **agentbrew** | Verifies agentbrew CLI/state sync and warns when registered MCP CLIs need local setup | `ai-tools` |
| **agent-browser** | agent-browser CLI installed, Chrome CDP responsive for browser automation | `ai-tools` |
| **chrome** | Chrome opens with Work profile by default; ChromeWork is kept as the system HTTP(S) handler so links from Slack, Mail, and Messages route there even when agent-browser Chrome daemons share the bundle | `enterprise` (both work-profile checks) |
| **devin** | Devin CLI binary, model consistency, config hygiene | `ai-tools` |
| **enterprise** | AWS CLI, Kubernetes, Gradle, Java 21, organization-specific tools + enterprise SSH config | `enterprise` |

> **Gate legend:** `enterprise` = requires `dotfiles enterprise on`. `ai-tools` = requires `use_ai_tools: true` in chezmoi config. Modules without a gate are available to all full-profile users.

## AI agent config

AI agent configuration (MCP servers, skills, rules, commands) is managed by [agentbrew](https://www.npmjs.com/package/agentbrew), not dotfiles. The `Agentfile.yaml` in this repo is the declarative manifest — see [Agentfile.yaml](Agentfile.yaml) for the full config and [docs/agentbrew-setup.md](docs/agentbrew-setup.md) for teammate setup and recovery. The no-argument `/learn-repos` command repairs its shared-memory connection before scanning and uses the `/ship-it` safety and ownership gates to deliver only source-backed repository healing.

Personal cross-tooling commands that should appear in every agent live in [`commands/`](commands/) — including `research-url`, `learn-repos`, and `ship-it`. `Agentfile.yaml` registers that directory so `agentbrew sync --agentfile ~/apps/dotfiles/Agentfile.yaml` deploys those commands to Claude Code, Cursor, Windsurf, Devin, and other command-capable agents. `/ship-it` requires visual proof for every PR. Use a browser screenshot for UI behavior or a terminal screenshot for non-UI behavior. Drag and drop the image into the PR description. Keep it outside the repository. `/learn-repos` takes no arguments: every invocation uses `bin/learn-repos-inventory` to select the next bounded batch under `~/apps`, protects active worktrees, refreshes missing or stale dossiers, extracts operational procedures, validates exact and hybrid retrieval, runs grounded evals, and resumes from memory on the next invocation. The helper detects repositories before pruning dependencies and lazily fingerprints only current-revision candidates, so a large fleet scan does not hang on unnecessary work.

The `update-tooling` skill safely refreshes primary tooling checkouts, applies the current dotfiles and agentbrew state, verifies machine health, and ranks the next AgentBrew or dotfiles task. It preserves dirty, ahead, diverged, and linked worktrees; it does not upgrade packages or publish work by default.

Do not put live authentication material or customer payload snapshots in test data,
logs, screenshots, pull request descriptions, or committed files. Use safe
placeholders and fixtures.

The `memory` MCP gives those agents one local cross-session store through pinned `mcp-memory-service` 11.7.0. AgentBrew owns the canonical `com.agentbrew.mcp-memory` LaunchAgent, its operator `HOME`, the loopback endpoint, MCP registration, and pack reconciliation; dotfiles contributes only the declarative `memory.enabled` intent and the pre-launch `cursor-at-login` gate. The endpoint is `http://127.0.0.1:18765/mcp`, so concurrent agents share one Python/ONNX process instead of launching a copy per chat. The login gate waits for the complete `initialize` → `notifications/initialized` → non-empty `tools/list` contract before opening Cursor, preventing a startup `ECONNREFUSED` or false-green partial probe from leaving the MCP stale for the whole IDE session. On macOS it persists at `~/Library/Application Support/mcp-memory/sqlite_vec.db` and uses SQLite WAL plus hybrid BM25/vector retrieval with RRF fusion. Behavioral bootstrap is enabled with a 1,536-token cap; the synced rules supply the current task, retrieve relevant context and mistake notes at session start, and automatically search current-revision procedure and repository memory before answering local architecture or operational questions. Agents refresh stale or missing knowledge from source docs, then commit structured decisions, errors, and corrections after substantive work. The service consolidates associations and summaries daily and weekly with forgetting disabled, while its built-in daily backups remain enabled. It never automatically archives raw transcripts or sends content to a cloud service.

Agent artifact coverage is enforced source-side: every `commands/*.md` file must have either `commands/evals/<command>.evals.json` or a literal Bats assertion, and `tests/agent-artifact-coverage.bats` also checks Agentfile command/rule/skill invariants plus `AGENTS.md`/`CLAUDE.md` delivery-safety mirroring. Add or update that coverage whenever changing command markdown, `Agentfile.yaml`, or global delivery rules.

Cursor Shell/Bash/Task commands pass through `agent-hooks/prepend-endpoint-path.sh` so endpoint-safe shims remain first in the sandbox PATH. The hook emits a fully materialized PATH rather than a dynamic `$PATH` expression, allowing downstream enterprise egress guards to classify literal `git push` and `gh` commands without weakening either policy layer.

On managed endpoints, uv Python may remain **Publisher: N/A** because python-build-standalone has no Developer ID authority; ad-hoc signing is not equivalent to publisher approval. Apply-time hook edits and high-frequency pre-tool JSON parsing use Apple-signed `plutil`; the pipx-based mcpm bridge and Python-dependent base/overlay doctors—including local-LLM checks—default to endpoint-policy safe mode. Set `DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=1` only after the machine-scoped exception is approved.

Official fnm Node can likewise be blocked by its upstream Developer ID, **Node.js Foundation (HX7739G8FX)**, regardless of its user-directory path. In that state, `dotfiles apply` skips agentbrew sync, unloads all `com.agentbrew.*` LaunchAgents plus the weekly Topgrade job, and weekly doctor skips Node-dependent modules. The Ollama supervisor independently refuses blocked publisher Team ID `3MU9H2V9Y9`. Set `DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1` or `DOTFILES_ALLOW_BLOCKED_OLLAMA_PUBLISHER=1` only after the corresponding machine-scoped exception is approved.

To keep agentbrew running while that publisher is blocked, set `DOTFILES_AGENT_NODE_BIN` to a Node from another publisher, for example `/opt/homebrew/bin/node`. When that binary exists and is not signed by the blocked publisher, `dotfiles apply` runs agentbrew sync on it, keeps the `com.agentbrew.*` LaunchAgents that run only that Node, and weekly doctor runs the agentbrew modules on it. The default `node` and the Topgrade safe mode do not change. A job whose program, or the first `node` on whose PATH, is the blocked Node stays off until agentbrew sync rewrites it.

Dotfiles exposes `agentbrew` as a real executable shim in `bin/agentbrew`, so it works from interactive zsh, non-interactive shells, launch agents, and agent tool calls. The shim reuses a local checkout at `~/apps/agentbrew` or `~/apps/tooling/agentbrew` and falls back to any later `agentbrew` binary on `PATH`.

**On `dotfiles apply`**, a chezmoi `run_after` script merges this file plus any overlay `Agentfile.yaml` into `~/.config/agentbrew/Agentfile.yaml`, then syncs agentbrew from that canonical global file when the installed `agentbrew` supports `agentfile merge`. On endpoint-policy-blocked Node publishers, that run exits in safe mode before executing Node. Older agentbrew releases fall back to the legacy safe path: sync the base Agentfile first, then sync the overlay with `--no-prune`. To sync manually on a merge-capable agentbrew:

```bash
agentbrew agentfile merge ~/apps/dotfiles/Agentfile.yaml --output ~/.config/agentbrew/Agentfile.yaml
agentbrew sync --agentfile ~/.config/agentbrew/Agentfile.yaml
```

If `agentbrew agentfile merge --help` does not show that subcommand yet, use:

```bash
agentbrew sync --agentfile ~/apps/dotfiles/Agentfile.yaml
agentbrew sync --agentfile ~/apps/dotfiles-<org>/Agentfile.yaml --no-prune
```

For a fresh machine, run `agentbrew init` first, then `agentbrew setup` for any MCP credentials, `dotfiles apply`, and `agentbrew status` to confirm generated config is healthy.

`dotfiles update` delegates agent-source refresh to `agentbrew sync --pull --agentfile ~/apps/dotfiles/Agentfile.yaml`; agentbrew remains the owner of generated agent config.

**Ownership boundary:** dotfiles owns shell, git, macOS, and editor settings. agentbrew owns MCP servers, skills, rules, and agent instructions.

**Agent public-write guard:** dotfiles wraps `gh` and `git` when `use_ai_tools` is enabled. Agent-shaped `gh pr create` calls must include a rationale and the canonical `_🤖 Written by an agent, not Fyodor..._` footer; cross-repo PR creation also requires an `AGENT_PUBLIC_WRITE_APPROVAL` marker that names the repo, base branch, title, and body hash. Agent-shaped GitHub pushes are limited to the exact repositories in `config/public-push-remotes.txt`; enterprise remotes pass through, and other public GitHub repositories are blocked. Agent-shaped `git push --no-verify` still requires the approval marker to cover the remote and ref. This is a user-owned backstop; the separately managed editor egress hook remains authoritative for editor sessions. Human interactive `gh` usage and read-only commands pass through unchanged.

**Approved-family delivery mandate:** in any tooling repo under `~/apps/tooling`, any own repo on `github.com/<owner>/*`, and any extra repo family the org overlay declares, agent-delivered work is not done until it is verified, committed, pushed to a feature branch, opened as a PR, watched through CI, and merged once checks are green. `/ship-it` explicitly covers all user-owned/current-session work in those approved repo families, not only the repo where the session began. In any other repository explicitly named by the active request, `/ship-it` also pre-approves normal feature-branch push/PR/CI delivery and rebasing a verified user-owned/current-session PR branch onto its actual base; rewritten branches must preserve the old remote OID and use explicit `git push --force-with-lease=<ref>:<old-oid>`. Product-repo delivery does not inherit the approved-family admin-bypass or release allowlist. `/ship-it` also resolves a clean canonical branch that is ahead/behind after delivery by preserving local-only commits, sending them through a PR branch, and only realigning the local branch after backup plus merge proof. If duplicate PRs/branches contain the same intended changes, the reviewed PR wins by default: move newer branch content onto the PR that already has human review history/comments/approvals, then close/supersede the duplicate only after the reviewed PR is open and complete; duplicate closure includes a reasoned closing comment with replacement links and head-branch deletion unless a documented exception applies. If sibling worktrees exist, `/ship-it` inventories them before cleanup, salvages any useful current-session/user-owned commits or dirty diffs into the winning PR/branch, proves already-represented work with `git cherry`/tree-diff/PR evidence, and removes only clean or redundant worktrees after that proof is recorded. For the four own-tool repos (`agentbrew`, `dotfiles`, `tasks.md`/`tasks-md`, and `minsky`), `/ship-it` also means run the repo-documented release path automatically after merge: agentbrew's auto-release plus `npm run publish-latest`, dotfiles' documented apply flow, tasks.md's GitHub Release-triggered npm publish workflow, and Minsky's semantic-release workflow when commit types warrant it. After tooling-repo delivery it also applies the machine's latest recommended updates — reconcile/rebuild the canonical tooling checkout per repo docs, run `agentbrew sync --pull` (recommended installs enabled by default) or `dotfiles apply` from a directory without a project Agentfile, and confirm `agentbrew status` is clean — because merged-but-not-applied tooling work leaves the machine running stale config. This is standing approval for approved-family branch pushes, PR creation/editing, guarded `git push --force-with-lease` PR-branch rewrites after preserving the old remote head and verifying ownership, safe cleanup of shipped/redundant current-session worktrees, and normal/admin PR merges for owned current-session work; when required checks are green, the PR is otherwise mergeable, and normal merge is blocked only by review/base-branch policy, the admin/bypass merge is required — do not leave the PR open or start a fresh branch for that policy-only blocker. It does not permit plain `--force`, hook bypasses, protected-branch pushes, unrelated branch deletion, secrets work, production/deployment changes, or publishing outside the current-task/approved repo scope.

**Linked Jira delivery:** when one Jira ticket governs the work, `/ship-it`
updates it after each successful final delivery milestone: review after the
final non-draft PR opens or becomes ready, then done after it merges. It uses
the configured team's available transition names and skips drafts, stack
children, and ambiguous or unrelated tickets.

**Adding an MCP server** (e.g. Jira/Atlassian) — deploys to **all agents** (Claude Code, Cursor, Windsurf, etc.) in one command:

```bash
agentbrew install atlassian          # installs mcp-atlassian across all detected agents
agentbrew setup atlassian            # interactive wizard: shows where to get each token, saves to ~/.zshenv.secrets
agentbrew sync                       # propagate to any agents added later
```

The setup wizard shows per-var instructions (description, link, numbered steps) and writes the tokens directly to `~/.zshenv.secrets`.

To share the setup with a colleague (gets Jira MCP in all their agents):

```bash
# On their machine:
npm install -g agentbrew
agentbrew init                       # detects Claude Code, Cursor, Windsurf, etc.
agentbrew install atlassian          # deploys to all detected agents globally
agentbrew setup atlassian            # guided wizard — tells you exactly where to get the tokens
agentbrew sync
```

The wizard walks through each required token (`JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`) with step-by-step instructions and a direct link to `id.atlassian.com/manage-profile/security/api-tokens`.

| Target | Owner | Notes |
|--------|-------|-------|
| `~/.zshrc`, `~/.gitconfig`, macOS defaults | **dotfiles** | Shell, git, system config |
| `~/.claude/`, `~/.cursor/mcp.json`, agent skills/rules | **agentbrew** | AI agent config via `Agentfile.yaml` |
| **Rule** | Never have both repos write to the same target path | |

See [AGENTS.md](AGENTS.md) for the full boundary table.

## LaunchAgents

After `dotfiles apply`, these agents run in the background. All are per-user (`~/Library/LaunchAgents/`) — no root privileges.

**Periodic tasks**

| Agent | Script | Schedule | What it does |
|-------|--------|----------|-------------|
| `com.dotfiles.cursor-priority` | `cursor-priority` | Every 60s | Prioritize interactive apps; background agent/model and verification workers so they yield under contention |
| `com.dotfiles.dotfiles-sync` | `dotfiles-sync` | Every 30 min | Auto-commit tracked/staged changes + push/pull dotfiles repo |
| `com.dotfiles.tooling-sync` | `tooling-sync` | Every hour | Pull agentbrew and minsky; push agentbrew TASKS.md edits |
| `com.dotfiles.network-resilience` | `network-watchdog` | Every 5 min + after wake | Restore DNS/connectivity after sleep |
| `com.dotfiles.heal-stuck-agents` | `dotfiles-heal-stuck-agents --fix --quiet` | Every 30 sec | Kill runaway Cursor helper crawls above 90% CPU after 60 sec; also heal hung git SSH + stale agent shells |
| `com.dotfiles.agent-keepawake` | `dotfiles-agent-keepawake` | Every 5s | Process-scoped `caffeinate -ims` + verified owned Amphetamine Closed-Display session while Cursor or Claude Code runs on AC or battery ≥20%; releases when both exit, and quarantines rejected scripting commands |
| `com.dotfiles.git-maintain` | `git-maintain` | Daily 4:00 AM | git gc, prune branches in `~/apps` repos |
| `com.dotfiles.morning` | `morning` | Daily 8:30 AM | Pull repos, health check, system summary |
| `com.dotfiles.dotfiles-doctor` | `dotfiles-doctor --fix` | Monday 9:00 AM | Auto-repair config drift and warn about stale Amphetamine Single-Use sleep blockers |
| `com.dotfiles.cleanup` | `cleanup` | Sunday 3:00 AM | Clear caches, logs, build artifacts |
| `com.dotfiles.dotfiles-upgrade` | `dotfiles-upgrade` | Sunday 9:00 AM | Topgrade: Homebrew, casks, tools (opt-in: `auto_upgrade: true`) |

**One LaunchAgent per job.** `dotfiles apply` unloads and deletes:

- a `com.dotfiles.*` agent that the current profile or config skips (for
  example `dotfiles-upgrade` when `auto_upgrade` is false);
- any other agent with the same command as a managed agent, or one that runs
  a script from this checkout (a legacy label prefix or a hand-installed copy).

`dotfiles doctor --module workflow` reports these as
`launchagents.no_duplicate_jobs`, and warns about other agents that only share
a managed agent's name (`launchagents.no_same_name_twins`).

**Persistent daemons (always running)**

| Agent | What it does |
|-------|-------------|
| `com.dotfiles.atuin-daemon` | Shell history sync daemon |
| `com.dotfiles.sleepwatcher` | Run scripts on sleep/wake events |
| `com.dotfiles.pmset-drift-watch` | Read-only: log each power-settings change with the processes alive at that moment (`logs/pmset-drift.log`) |

**Login-time (run once at login)**

| Agent | What it does |
|-------|-------------|
| `com.dotfiles.capslock-control` | Remap CapsLock to Control |
| `com.dotfiles.gui-path` | Export PATH to GUI session environment |
| `com.dotfiles.cursor-at-login` | Launch Cursor in background (`open -g -a Cursor`, no focus steal) |
| `com.dotfiles.rancher-desktop` | Start Rancher Desktop, keep Kubernetes off, wait until the Docker API answers (one restart if it does not) |

**Browser automation (started at login, not kept alive — attach via CDP)**

| Agent | What it does |
|-------|-------------|
| `com.dotfiles.agent-browser-chrome` | Dashboard / SSO Chrome on port 9223 |
| `com.dotfiles.debug-chrome` | Debug-work Chrome on port 9224 |
| `com.dotfiles.tooling-chrome` | Tooling-repo Chrome on port 9225 |

Agent browser work is attach-first: normal `agent-browser` calls and dotfiles-assigned agent sessions attach to the dashboard Chrome on `9223` when it is reachable. Use the purpose Chrome directly for specialized work (`9224` for debug work, `9225` for tooling) and keep own-tab discipline: open your own tab, work only there, and close extra tabs at task end. Use a stable purpose-named headed session only for true isolation or conflicting credentials; never use timestamp-unique SSO sessions.

The three managed Chromes are `RunAtLoad` only, with `KeepAlive=false`. If you quit Chrome while shutting down or logging out, launchd and `dotfiles doctor --fix` must not reopen it. They come back on the next login, or you can restart one explicitly with `launchctl start <agent-label>`.

**On-demand (loaded but not auto-started — start with `launchctl start <label>`)**

| Agent | What it does |
|-------|-------------|
| `com.dotfiles.chrome-debug` | Chrome with debug port 9222 (separate profile) |

**Disabling an agent:**

```bash
launchctl unload ~/Library/LaunchAgents/<agent-label>.plist
```

To re-enable: `launchctl load ~/Library/LaunchAgents/<agent-label>.plist`. Browser automation agents can also be restarted explicitly with `launchctl start <agent-label>`; `dotfiles doctor --fix` does not reopen them after a manual close.

## Fork & customize

This repo is designed for team adoption. Fork it, then run through the setup:

> **Adopting for your team?** See the [Forking & Adoption Guide](docs/forking-guide.md) for what to keep, remove, and customize.
>
> **Adopting inside your company?** Use [docs/team-onboarding.md](docs/team-onboarding.md) for pilot sizing, GitHub Enterprise, VPN, and support-channel checks.
>
> **Already have dotfiles?** See the [migration guide](docs/migration.md) for moving from plain symlinks, Stow, yadm, or bare git repos.

1. **Fork and clone:**
   ```bash
   git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles
   ```

2. **Initialize chezmoi:** You'll be prompted for profile (`core` or `full`), enterprise toggle, AI tooling opt-in, and optional age encryption.
   ```bash
   chezmoi init --source ~/apps/dotfiles --apply
   ```

3. **Set up personal git config:** Copy the example and fill in your name/email:
   ```bash
   cp ~/apps/dotfiles/gitconfig.local.example ~/.gitconfig.local
   # Edit ~/.gitconfig.local with your details
   ```

4. **Add personal shell config** (optional):
   ```bash
   touch ~/.zshrc.local
   # Add personal aliases, tokens, organization-specific PATH entries
   ```

5. **Run doctor to verify:**
   ```bash
   dotfiles doctor --fix
   ```

### Common customizations

**Add a Homebrew package:**

```bash
dotfiles brew-add ripgrep                  # CLI tool
dotfiles brew-add firefox --cask           # GUI app
dotfiles brew-add gradle --full-only       # only in full profile
```

This adds the package to the Brewfile and creates a doctor check for it.

**Add a macOS default:**

```bash
dotfiles defaults-add com.apple.dock tilesize 48 int
```

This adds the `defaults write` to `macos.sh` and a `check_defaults` entry in the macos doctor module.

**Create a new doctor module:**

```bash
dotfiles new-module mytools --severity important
```

This scaffolds `modules/mytools/doctor.sh` with a template. Add `check` calls and they're auto-discovered by `dotfiles doctor`.

**Disable a specific health check:**

```bash
dotfiles doctor --skip chrome.devtools     # permanently skip this check
dotfiles doctor --skip enterprise.aws      # skip if you don't use AWS
```

Skips are stored in `~/apps/dotfiles/.overrides`. `--skip` rejects unknown IDs
without changing that file; run `dotfiles doctor --list` to discover valid IDs.
Remove a line to re-enable a skipped check.

**Filter by severity (CI / fast feedback):**

```bash
dotfiles doctor --severity critical       # only critical-tier modules — fast, gating
dotfiles doctor --severity important      # critical + important (default sweet spot)
dotfiles doctor --severity cosmetic       # everything (default)
```

Each module declares a tier via a one-line `modules/<name>/severity` file (default: `cosmetic`). Tiers cascade: `--severity critical` runs only critical-tagged modules; `--severity cosmetic` runs every tier. Useful for CI jobs that want to block on `critical` only without skipping the rest of the suite. See [docs/module-reference.md](docs/module-reference.md#severity-tiers) for what each tier means.

See [docs/onboarding.md](docs/onboarding.md) for the full onboarding guide.

## How it works

### File modes

| Source naming | Mode | Deployed as |
|--------------|------|-------------|
| `symlink_dot_*.tmpl` + `home/*` | Symlink | `~/.<name>` → `home/<name>` (edit in place) |
| `dot_*` | Copy | `~/.<name>` (run `dotfiles apply` after editing) |
| `private_dot_*` | Private copy (0700) | `~/.<name>` |
| `encrypted_*.age` | Encrypted | Decrypted at apply time |
| `*.tmpl` | Template | Rendered with chezmoi data |

### Personal overrides

Files you should customize are kept separate and never overwritten:

- `~/.gitconfig.local` — your name, email, org-specific URLs
- `~/.zshrc.local` — personal aliases, tokens, organization-specific PATH entries

### How config is stored

| | **Dotfiles repo** | **Deployed config** |
|---|---|---|
| **Path** | `~/apps/dotfiles/` | `~/.*`, `~/.config/*` |
| **What's in it** | Source of truth — all config, scripts, modules, tests | Symlinks or copies managed by chezmoi |
| **Who edits it** | You — edit source files, run `dotfiles apply` | Chezmoi — deploys from source on apply |
| **Commit to git?** | **Yes** — this is your portable config | **No** — regenerated on every apply |

## How dotfiles compares

| Feature | This repo | Plain chezmoi | GNU Stow | Nix/home-manager |
|---------|-----------|---------------|----------|-----------------|
| **Self-healing** | Checks auto-discovered per module | No health checks | No health checks | Nix guarantees state |
| **macOS defaults** | 149 `defaults write` via lifecycle scripts | Not included | Not included | Via nix-darwin (separate tool) |
| **Profile picker** | Interactive prompt at init time | Manual `.chezmoiignore` editing | Manual stow/unstow | Declarative config file |
| **Time tracking** | Automated stats (runs, time saved, streak) | Not included | Not included | Not included |
| **LaunchAgents** | Sync, cleanup, maintenance | Not included | Not included | Via launchd module |
| **Secrets** | age encryption (builtin, zero deps) | age/gpg encryption | Not included | agenix/sops-nix |
| **Cross-platform** | macOS only (focused) | Linux + macOS + Windows | Linux + macOS | Linux + macOS |

**Our niche:** chezmoi handles file management; we add macOS tuning, self-healing health checks, and automation tracking on top.

## Performance

Shell startup is benchmarked on every CI run and must stay under 200ms. The badge at the top reflects this threshold. Check the latest result in the [CI doctor job summary](https://github.example.com/your-org/dotfiles/actions/workflows/ci.yml).

Measured on M3 Max, 64GB RAM, 300+ package JS/TS monorepo:

| Operation | Before | After | What changed |
|---|---|---|---|
| Shell startup | ~300ms | ~30ms | fnm replaces NVM, tool inits cached |
| `git status` (monorepo) | ~500ms | ~80ms | histogram diff, parallel index, maintenance strategy |
| TypeScript incremental build | ~15s | ~3s | FSEvents watch, Babel cache, UV_THREADPOOL=16 |
| `npm install` (warm cache) | ~45s | ~20s | maxsockets=50, IPv4-first DNS |
| WebStorm GC pauses | 100–500ms random | <1ms | ZGC replaces G1GC |
| Background CPU at idle | ~30% | ~5–8% | Spotlight pruning/exclusions, analytics off, AirPlay off |

### Interactive terminal responsiveness

Ghostty keeps scrollback in memory for every terminal surface. The managed
config uses Ghostty's upstream 10 MB cap to prevent verbose commands from
retaining 100 MB per tab. The `cursor-priority` LaunchAgent runs every minute:
it keeps Ghostty, WebStorm, and Claude Code launched from a WebStorm terminal
interactive while unrelated agent and model workers yield under CPU contention.

WebStorm terminals identify themselves as `JetBrains-JediTerm`. Their default
fast shell resolves the default fnm Node directly and loads only the
Claude-facing environment. It skips fnm's per-directory setup, full interactive
helpers, completion, and local-MLX startup so Claude Code can open without
competing work. Run `dotfiles-full-shell` in that terminal if you need aliases,
interactive completion, or Node switching after changing directories.

This improves scheduling fairness. macOS does not reserve CPU cores or RAM for
an app. If you create `~/.config/dotfiles/priority-apps.txt`, it replaces the
default app list; include `ghostty` and `WebStorm` to keep this policy.

## CLI reference

```
dotfiles apply                                    Apply dotfiles (chezmoi apply)
dotfiles init                                     Initialize on new machine (chezmoi init --apply)
dotfiles diff                                     Show pending changes (chezmoi diff)
dotfiles update [--dry-run] [--verbose]           Whole-machine update (pull/apply/agentbrew/packages/doctor)
dotfiles upgrade [--dry-run]                      Upgrade all software (brew, casks, macOS, tools)
dotfiles doctor [--fix] [--fix-all] [--skip ID] [--list] [--quiet] [--report]
                [--module X] [--severity LEVEL] [--json] [--watch] [--validate-overrides] [--trends]
                                                              Audit configs, optionally auto-fix drift
dotfiles audit [--report]                         Security audit (SSH, secrets, permissions, git)
dotfiles validate [--quick]                       Pre-share verification (paths, secrets, lint, test)
dotfiles defaults-preview [--changed]             Preview macOS defaults changes (no writes)
dotfiles sync                                     Commit tracked/staged local changes + pull remote
dotfiles managed                                  List all managed files
dotfiles status                                   Git status of dotfiles repo
dotfiles stats [--oneliner] [--recalc]            Automation stats (runs, time saved, streak)
dotfiles edit                                     Open dotfiles repo in $EDITOR
dotfiles cheat                                    Command reference card

dotfiles add <file> [--copy] [--module M]         Add a config file
dotfiles unmanage <file>                          Remove a managed file
dotfiles new-module <name> [--severity S]         Create a doctor module
dotfiles brew-add <pkg> [--cask] [--full-only]    Add a Homebrew package
dotfiles defaults-add <domain> <key> <val> <type> Add a macOS default
dotfiles profile [core|full]                      Show or switch profile
dotfiles enterprise [on|off]                      Toggle enterprise mode
dotfiles quickstart [--check]                     Interactive first-run wizard (guided setup)
dotfiles uninstall [--dry-run]                    Remove dotfiles from this machine
dotfiles cd                                       Print dotfiles directory (use: cd $(dotfiles cd))
```

### Standalone scripts

These scripts are added to `PATH` via `bin/` and can be run directly. Scripts marked with a schedule run automatically via LaunchAgent.

**Automation (LaunchAgent-driven)**

| Script | Description | Schedule |
|--------|-------------|----------|
| `cleanup` | Reclaim disk from caches, logs, and build artifacts | Weekly (Sun 3 AM) |
| `cursor-priority` | Prioritize interactive apps and background agent/model workers | Every 60 seconds |
| `git-maintain` | git gc, fetch, prune branches and fix worktrees in `~/apps` repos | Daily |
| `morning` | Pull repos, health check, notes, disk and CPU summary | Daily (8:30 AM) |
| `network-watchdog` | Verify and restore connectivity with signed native TCP probes | Every 5 min + after wake |
| `rancher-desktop` | Start Rancher Desktop and wait until the Docker API answers | At login |
| `dotfiles-pmset-drift-watch` | Log who changed power settings (read-only) | On power-plist write + every 5 min |

**Git workflow**

| Script | Description |
|--------|-------------|
| `git-safe` | Guard destructive git commands in multi-agent repos |
| `hotfix` | Branch from main, stash current work, prep a quick hotfix |
| `land` | Human-only: push feature branches of github.com checkouts whose push URL is `DISABLED`, and open their PRs |
| `pr` | Commit tracked/staged changes, push, and open a draft GitHub PR |
| `review` | Checkout a PR, show diff, optionally run tests |

`dotfiles sync` and `pr` never auto-stage untracked files. Stage a new file
explicitly with `git add <path>` when you want those helpers to include it;
otherwise untracked files are left alone to avoid committing another agent's
scratch work.

**Development setup**

| Script | Description |
|--------|-------------|
| `new-project` | Scaffold a react/node/lib/python project with best-practice defaults |
| `setup-chrome` | Apply dev-friendly Chrome settings and performance flags |
| `setup-dock` | Reset Dock to a developer-essential app layout |

**Utilities**

| Script | Description |
|--------|-------------|
| `cheat` | Quick cheatsheet for all custom commands and shortcuts |
| `note` | Append timestamped notes to a daily markdown file |
| `status` | System dashboard: fastfetch, dotfiles version, agent status |
| `timer` | Pomodoro-style countdown timer with macOS notification |
| `graceful-restart` | Wait for active processes to finish, then restart macOS |

**Build and test infrastructure**

| Script | Description |
|--------|-------------|
| `bats-affected` | Print bats test files affected by current git changes |
| `cached-run` | Skip commands when the git working tree hasn't changed |
| `check-all` | Run cached lint and test across all `~/apps` repos |

## Environment variables

User-configurable variables that customize dotfiles behavior. Set them in `~/.zshrc.local` or your shell profile.

| Variable | Default | Purpose |
|----------|---------|---------|
| `DOTFILES_REPOS_DIR` | `$HOME/apps` | Directory containing git repos for `morning`, `git-maintain`, and doctor checks |
| `DOTFILES_STATS_FILE` | `$HOME/.dotfiles-stats.jsonl` | JSON Lines file tracking automation statistics (time saved, runs) |
| `DOTFILES_CI` | `false` | Set to `true` in CI to skip macOS-specific checks (spotlight, pager, etc.) |
| `DOTFILES_DOCTOR_NOTIFY` | `0` | Set to `1` to enable macOS notification banners after `dotfiles-doctor` runs (failures and `--fix` successes). Default off; logs and exit codes unchanged. |
| `DOTFILES_NETWORK_TARGETS` | Anthropic, GitHub, Devin URLs | Space-separated URLs for network watchdog connectivity checks |
| `TERMINAL_LOG` | (unset) | Set to `1` to enable terminal session logging to `~/.local/share/terminal-logs/` |
| `FIX_TIMEOUT` | `30` | Seconds to wait for each auto-fix command in `dotfiles doctor --fix` |
| `EDITOR` | `vim` | Default editor for git commits and `dotfiles edit` |
| `GIT_SAFE_BYPASS` | (unset) | Set to `1` to bypass git-safe guards: `GIT_SAFE_BYPASS=1 git reset --hard` |
| `NO_COLOR` | (unset) | Disable ANSI colors in all dotfiles output ([no-color.org](https://no-color.org/)) |
| `FORCE_COLOR` | (unset) | Force ANSI colors even when stdout is not a TTY |

**AI tooling** (available when `use_ai_tools: true` in chezmoi config):

| Variable | Default | Purpose |
|----------|---------|---------|
| `DEVIN_MODEL` | `gpt-5-5-xhigh-priority` | Devin CLI model (`GPT-5.5 XHigh Thinking Fast`) — see [`AGENTS.md` § Model Configuration](AGENTS.md#model-configuration) for the per-agent model policy |
| `AGENT_BROWSER_IDLE_TIMEOUT_MS` | `600000` | Keep agent-browser daemon alive (ms) between commands |
| `AGENT_BROWSER_DEFAULT_TIMEOUT` | `15000` | Page load timeout (ms) for agent-browser |
| `AGENT_BROWSER_SESSION` | (auto-set for agents) | Stable daemon/session identity. Dotfiles-assigned agent sessions attach to `--cdp 9223` by default; a caller-provided value is the explicit isolation escape hatch for non-SSO work. |
| `AGENT_BROWSER_PROFILE` | (unset) | Optional custom profile for non-managed launches. Must not point at launchd-owned profiles under `~/.agent-browser/{chrome-profile,debug-profile,tooling-profile}`; the shell wrapper converts those to `--cdp` attach or refuses. |
| `AGENT_BROWSER_NO_AUTO_CDP` | (unset) | Opt out of default/implicit-session auto-attach to port 9223. Does not permit launching against launchd-owned profiles. |
| `AGENT_BROWSER_ALLOW_FOCUS` | (unset) | When set (or with `--headed`), skip post-command focus-steal logging. Headless CDP is the default; dotfiles never hides Chrome or re-activates your prior app. |
| `AGENT_BROWSER_ARGS` | (unset globally) | Optional launch args for cold-path agent-browser Chrome spawns only. The shell wrapper sets `--headless=new` inline on the cold path; it is cleared on `--cdp` attach so launchd Chromes never inherit extra flags. |
| `HEAL_RUNAWAY_AGENT_MAX_CPU_PERCENT` | `90` | Maximum CPU percentage (100% = one core) allowed for Cursor's non-interactive `rg --files --follow` ignore-discovery helper after the grace period. |
| `HEAL_RUNAWAY_AGENT_MIN_AGE_SEC` | `60` | Grace period before a helper over the CPU threshold is treated as runaway and terminated. |

**Enterprise secrets** (set in `~/.zshenv.secrets`, never tracked in git):

| Variable | Purpose |
|----------|---------|
| `SPLUNK_MCP_URL` | Splunk MCP server endpoint |
| `JENKINS_URL` / `JENKINS_USER` / `JENKINS_TOKEN` | Jenkins CI credentials |
| `GITHUB_TOKEN` | GitHub Personal Access Token |
| `JIRA_PERSONAL_TOKEN` | JIRA API token (or use `jira-token` Keychain helper) |

## Repo layout

```
dotfiles/
├── home/                        Actual config content (symlinked to ~/)
├── bin/                         Scripts (38+ — added to PATH)
├── modules/                     Health check modules
│   └── */doctor.sh              Per-module checks using check(), check_symlink(), check_managed()
├── lib/                         Shared libraries (colors.sh, stats.sh, output.sh)
├── macos.sh                     Core macOS defaults
├── macos-visual.sh              Visual prefs, full only
├── macos-apps.sh                App-specific prefs, full only
├── launchagents/                macOS scheduled task templates
├── .chezmoiscripts/             Lifecycle scripts (brew, macos, launchagents, agentbrew)
├── dot_*                        Copy-mode config files (→ ~/.<name>)
├── private_dot_ssh/             SSH config (restricted permissions)
├── symlink_dot_*.tmpl           Symlink templates (→ ~/.<name>)
├── tests/                       bats test suite
├── docs/                        User stories, RFC, security model
└── .github/workflows/           CI definitions: shellcheck + bats + doctor + brew audit (not run today)
```

See [AGENTS.md](AGENTS.md) for the detailed repo layout with ownership boundaries and data flow.

## Development

```bash
make lint           # shellcheck all scripts
make lint-tasks     # validate TASKS.md queue format + P0/P1 rule-9 fields
make test           # affected tests only (cached, git-aware)
make test-all       # full suite (cached)
make test-force     # full suite, no cache
make check          # lint + TASKS.md lint + test (run before committing)
make install-deps   # install dev dependencies (required + optional tools)
make fmt            # format shell scripts with shfmt
make count          # show test, module, and check counts
make coverage       # run tests via bin/dotfiles-coverage and enforce .shell-coverage-floor
make clean          # remove test cache and tmp artifacts
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for architecture and editing rules. See [TASKS.md](TASKS.md) for the backlog.

### Where tests run

Bats and shellcheck run only on a developer machine, through `make check`. The workflows in `.github/workflows/` do not run anywhere today:

- **`fyodoriv/dotfiles`**: Actions is turned off, so no workflow runs on pushes or PRs.

So run `make check` (or the affected `bats` files) before you push, and paste the result in the PR test plan.

`make install-deps` installs the Homebrew tools used by local validation:
required for `make check`/tests (`shellcheck`, `bats-core`, `parallel`,
`chezmoi`, `fd`, `jq`) plus the optional `shfmt` helper
for `make fmt`.
`make coverage` is served by the in-tree `bin/dotfiles-coverage` harness, so
no extra Homebrew formula is required there. The shared coverage floor lives
in `.shell-coverage-floor`; set it from the latest full `make coverage`
percentage with at most a 1.0 point buffer, then raise it only in changes that
add or strengthen tests. `make lint-tasks` uses the pinned
`@tasks-md/lint` version from `.tasks-lint-version` and then enforces
single-line `Hypothesis`, `Success`, `Pivot`, `Measurement`, and `Anchor`
fields on every P0/P1 task, so keep Node/npm available through your normal
Node manager.

The monthly Brew manifest audit can be rerun locally without installing every
package:

```bash
.github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
BREW_AUDIT_SKIP_LIVECHECK=1 .github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl
```

Livecheck calls have a per-entry timeout; use the skip mode for metadata-only
reruns when Homebrew networking is slow.

### For developers

| Document | Contents |
|----------|----------|
| [AGENTS.md](AGENTS.md) | Codebase guide, repo layout, ownership boundaries (for AI agents and contributors) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development workflow, architecture, and editing rules |
| [docs/ci-setup.md](docs/ci-setup.md) | CI configuration for team forks (GH Actions, GHE, branch protection) |
| [docs/architecture.md](docs/architecture.md) | End-to-end system architecture, data flow, module discovery |
| [docs/security-model.md](docs/security-model.md) | Trust boundaries, privilege escalation, secrets handling |
| [docs/module-reference.md](docs/module-reference.md) | Every health check, by module |
| [docs/forking-guide.md](docs/forking-guide.md) | How to fork and adapt for your team |
| [docs/migration.md](docs/migration.md) | Migrating from plain symlinks, Stow, yadm, bare git repos |
| [docs/workspace.md](docs/workspace.md) | Multi-workspace discovery and the `dotfiles-workspace status` rollup |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Symptom-first troubleshooting with causes and fixes |

## Troubleshooting

> **Full guide**: [docs/troubleshooting.md](docs/troubleshooting.md) — symptom-first entries with causes and fixes.

Quick fixes for the most common issues:

| Symptom | Fix |
|---------|-----|
| Shell takes >200ms to start | `dotfiles doctor --fix --module shell` (regenerates caches) |
| `command not found: brew` | Install Homebrew, then `source ~/.zshrc` |
| `dotfiles doctor` fails on first run | `dotfiles doctor --fix` (auto-repairs most checks) |
| `chezmoi init` fails with age error | Re-run init with `use_encryption: false`, or generate a key first |
| LaunchAgents not loading | `dotfiles doctor --fix --module workflow` |
| Git is slow | `dotfiles doctor --fix --module git` (disables fsmonitor) |
| `~/.gitconfig.local` not found | Create it with your `[user] name` and `email` |

> For organization-specific issues (SSH to github.example.com, enterprise module failures), see your org overlay's onboarding guide.

## FAQ

### Will `chezmoi apply` overwrite my changes?

No. Symlinked files point directly to `home/*` in this repo — chezmoi only manages the symlink. Copy-mode files are overwritten, but `dotfiles diff` always shows what would change.

### Where do I put personal secrets?

In `~/.zshenv.secrets` — this file is gitignored and sourced automatically by `~/.zshenv`. See `home/zshenv.secrets.example` for the template. For encrypted secrets, use chezmoi's age encryption (`encrypted_*.age`).

### Where do I put personal aliases?

`~/.zshrc.local` — sourced at the end of `.zshrc`, gitignored, never overwritten.

### How do I add a new tool?

```bash
dotfiles brew-add <package>              # adds to Brewfile + doctor check
dotfiles brew-add <package> --cask       # GUI app
dotfiles brew-add <package> --full-only  # only in full profile
```

### How do I switch profiles?

```bash
dotfiles profile full    # switch to full
dotfiles profile core    # switch to core
dotfiles profile         # show current
```

Then `dotfiles apply` to deploy.

### What's the difference between dotfiles and agentbrew?

| Concern | Owner |
|---------|-------|
| Shell, git, macOS, SSH, editor config | **dotfiles** |
| AI model defaults (`DEVIN_MODEL`, Claude Code model pin, Cursor model parity) | **dotfiles** (opt-in via `use_ai_tools`) |
| AI agent MCP servers, skills, rules, commands | **agentbrew** |

Rule: never have both repos write to the same target path.

### `dotfiles doctor` shows failures — is that bad?

Not always. Common benign failures: `enterprise.*` checks (only if enterprise enabled), `claude.*` / `cursor.*` (run `agentbrew sync`), `agent.*` (run `dotfiles doctor --fix`). Use `--skip <id>` to permanently dismiss.

### How do I check just one module?

```bash
dotfiles doctor --module git         # only git checks
dotfiles doctor --fix --module ssh   # fix SSH checks only
```

### How do I see all check IDs?

```bash
dotfiles doctor --list               # all check IDs across all modules
```

Each ID follows the pattern `<module>.<check>` (e.g., `tool.delta`, `ssh.agent_keychain`). Use these IDs with `--skip` to permanently dismiss individual checks; typos are rejected without changing `.overrides`.

### What if I don't enable enterprise mode?

Everything works fine without it. Enterprise mode adds AWS CLI, Kubernetes tools, Gradle, Java 21, and enterprise SSH config — tools needed for backend/infrastructure work. If you're a frontend developer or don't need cloud tooling, skip it. You can enable it later with `dotfiles enterprise on`.

### How do I permanently skip a check?

```bash
dotfiles doctor --skip tool.delta     # skip the delta check forever
```

Skips are stored in `~/apps/dotfiles/.overrides`. `--skip` validates the ID
against `dotfiles doctor --list`, avoids duplicate entries, and leaves the file
unchanged on typos. Remove a line to re-enable.

### Where are doctor logs?

The weekly doctor LaunchAgent writes to `~/Library/Logs/dotfiles-doctor.log`. View with:

```bash
cat ~/Library/Logs/dotfiles-doctor.log
```

## Releases

Tagged with [semver](https://semver.org/). Pushing a tag triggers `.github/workflows/release.yml` to auto-generate a changelog from conventional commits.

```bash
make check && git tag vX.Y.Z && git push origin vX.Y.Z
```

- **Major** — breaking changes to CLI or chezmoi source layout
- **Minor** — new commands, modules, or features
- **Patch** — bug fixes, doc updates

## License

MIT

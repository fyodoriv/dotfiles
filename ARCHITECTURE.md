# Architecture

> Root-level architecture summary the `load-project-context` rule expects. The detailed walkthrough lives in [`docs/architecture.md`](docs/architecture.md); this doc is the index + system-level overview a fresh contributor needs before opening any script.

## System overview

```
                       ┌─────────────────────────────────┐
                       │  ~/apps/dotfiles/                │
                       │    home/ + dot_* + symlink_*    │  ← Source of truth
                       │    .chezmoiscripts/              │     (committed)
                       │    macos*.sh, launchagents/      │
                       │    Agentfile.yaml                │
                       └────────────────┬────────────────┘
                                        │  chezmoi apply
                                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ chezmoi sync engine (symlink / copy / template / encrypted)  │
   └──────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ ~/.zshrc → home/zshrc       ~/.gitconfig → home/gitconfig    │
   │ ~/.config/ghostty/          ~/.config/starship.toml          │
   │ ~/Library/LaunchAgents/com.dotfiles.*                        │
   │ macOS defaults (Finder, Spotlight, keyboard, …)              │
   │ Brewfile-managed packages + casks                            │
   └──────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ Agentfile.yaml  →  agentbrew sync  →  ~/.claude/, ~/.cursor/  │
   │                                       ~/.codex/, …           │
   │                              (every agent surface in Agentfile) │
   └──────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
   ┌──────────────────────────────────────────────────────────────┐
   │ dotfiles-doctor (per-module checks, --fix per-check)          │
   │   auto-detects drift; offers to repair; surfaces gaps        │
   └──────────────────────────────────────────────────────────────┘
```

The 5-layer stack: source → chezmoi → host filesystem → agent-config (via agentbrew) → self-healing (via doctor).

## Layered structure

| Layer | Owner | Files |
|---|---|---|
| **Source content** | dotfiles | `home/*`, `dot_*`, `symlink_dot_*.tmpl`, `private_dot_ssh/`, `encrypted_*.age` |
| **Lifecycle scripts** | dotfiles | `.chezmoiscripts/run_*.sh.tmpl` (bootstrap, brew, macos, launchagents, agentbrew-sync, local-LLM) |
| **Modules (doctor checks)** | dotfiles | `modules/<name>/doctor.sh` (auto-discovered by `dotfiles-doctor`) |
| **CLI surface** | dotfiles | `bin/*` (`dotfiles`, `dotfiles-doctor`, `dotfiles-sync`, `dotfiles-stats`, `morning`, `cleanup`, `git-maintain`, `cheat`, etc.) |
| **Test surface** | dotfiles | `tests/*.bats` |
| **Agent manifest** | dotfiles | `Agentfile.yaml` (declares MCP servers / skills / sources for agentbrew) |
| **Generated agent config** | **agentbrew** (NOT dotfiles) | `~/.claude/`, `~/.cursor/`, `~/.codex/`, … |

The boundary between dotfiles and agentbrew is in [`AGENTS.md` § "Ownership Boundary"](AGENTS.md#ownership-boundary). Iron rule: **never have both repos write to the same target path.**

## chezmoi mapping (source → host)

| Source pattern | Mode | Target |
|---|---|---|
| `symlink_dot_*.tmpl` + `home/*` | symlink | `~/.<name>` → `home/<name>` (live edits) |
| `dot_*` | copy | `~/.<name>` (edits require `chezmoi apply`) |
| `private_dot_*` | private copy (0700) | `~/.<name>` |
| `encrypted_*.age` | age decryption + copy | `~/.<name>` |
| `dot_config/*` | copy | `~/.config/<name>` |
| `.chezmoiscripts/run_*` | lifecycle script | runs on `chezmoi apply` (once / onchange / always) |

Detail in [`docs/architecture.md`](docs/architecture.md) (the canonical narrative).

## Doctor module pattern

Each module under `modules/<name>/doctor.sh` is auto-discovered by `dotfiles-doctor` and runs in dependency order. Modules use the shared `lib/output.sh` helpers (`check()`, `check_symlink()`, `check_managed()`) so output stays uniform.

```bash
modules/
├── agentbrew/doctor.sh        # CLI present, Agentfile valid, state.yaml in sync
├── git/doctor.sh              # user.email public-safe, hooks active, no leak refs
├── shell-startup/doctor.sh    # <200ms startup; alerts on regression
├── starship/doctor.sh         # config present + valid TOML
├── ghostty/doctor.sh          # config + Mac-permission grants
├── ai-tools/doctor.sh         # agent CLIs installed (opt-in)
├── local-llm/doctor.sh        # Ollama + qwen3-coder healthy
├── memory/doctor.sh           # shared MCP, maintenance, backup integrity
├── security/doctor.sh         # endpoint-policy compliance: no Python.framework pipx
└── … (12 more)
```

Adding a new module is one file + auto-discovery — no central registry.

## Remote + privacy architecture

One remote:

| Remote | URL | Branch | Push path |
|---|---|---|---|
| `origin` | `github.com/fyodoriv/dotfiles` | `feat/chezmoi` (canonical, GitHub default) | feature branch → `git push origin <branch>` → PR → merge |

Nothing rewrites history. The privacy gates run before a
commit leaves the machine:
1. `git-hooks/pre-commit` blocks forbidden files, private identifiers, secrets, and private committer emails
2. `git-hooks/pre-push` blocks commits whose author or committer email matches the private-email pattern, for pushes of dotfiles, agentbrew, and every repo in `config/public-push-remotes.txt` to github.com; it also blocks private references in pushed file contents, file names, and commit messages
3. Both private patterns come from the org overlay's `oss-readiness.env`; with no overlay, those checks have nothing to match

Full design in [`SECURITY.md`](SECURITY.md).

## Agentfile lifecycle

`Agentfile.yaml` at repo root declares the machine's MCP servers, skills, rules, and sources. On `chezmoi apply`, `.chezmoiscripts/run_after_agentbrew-sync.sh` runs `agentbrew sync --agentfile ~/apps/dotfiles/Agentfile.yaml` (or the `tsx ~/apps/agentbrew/src/cli.ts sync` fallback). The `agentbrew` doctor module verifies the result.

The `EXTRA_AGENTFILE` env var loads an org overlay (`~/apps/dotfiles-<org>/Agentfile.yaml`) without forking the core repo. Org-gated MCPs DO NOT belong in this repo's Agentfile — see [`AGENTS.md` § "Agentfile Lifecycle"](AGENTS.md#agentfile-lifecycle).

## Verification

| Surface | Gate |
|---|---|
| Scripts (`bin/*`, `modules/*`, `.chezmoiscripts/*`) | `make lint` (shellcheck) |
| `TASKS.md` edits | `make lint-tasks` (tasks-md spec linter) |
| Doctor modules | `make test` (bats suite, cached) |
| Full pre-commit gate | `make check` (lint + lint-tasks + test) |
| `Agentfile.yaml` edits | `agentbrew sync --agentfile ~/apps/dotfiles/Agentfile.yaml` |
| Privacy guard | `bats tests/no-internal-refs.bats tests/oss-readiness-lib.bats` |

Detail in [`AGENTS.md` § "Verification Gates"](AGENTS.md#verification-gates).

## Where to read next

| You're here to… | Read |
|---|---|
| Understand chezmoi mapping in detail | [`docs/architecture.md`](docs/architecture.md) |
| Set up dotfiles from a fresh Mac | [`docs/onboarding.md`](docs/onboarding.md) |
| Add a new module | [`docs/module-reference.md`](docs/module-reference.md) |
| Fork for your company | [`docs/forking-guide.md`](docs/forking-guide.md) |
| Configure agentbrew integration | [`docs/agentbrew-setup.md`](docs/agentbrew-setup.md) |
| Understand the privacy contract | [`SECURITY.md`](SECURITY.md) |
| Set up multi-machine sync | [`docs/multi-machine.md`](docs/multi-machine.md) |
| Troubleshoot symptoms | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| Read process rules | [`AGENTS.md`](AGENTS.md) + [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| Track local-LLM upstream | [`docs/local-ai-roadmap.md`](docs/local-ai-roadmap.md) |

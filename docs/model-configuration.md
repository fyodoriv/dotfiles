# Model configuration

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## Model Configuration

Each agent keeps its own default model. Do not infer a cross-agent model change from a change to one agent.

| Agent | Default tier | Identifier string | Config location | Owner |
|-------|--------------|-------------------|-----------------|-------|
| **Claude Code** | XHigh | `claude-opus-5-5` + `effortLevel: "xhigh"` (per-machine override below) | `~/.claude/settings.json` | **dotfiles** (`.chezmoiscripts/run_after_claude-settings-model.sh` + `modules/claude/doctor.sh` → `claude.model_default`; `Agentfile.yaml` `defaultModel`/`defaultEffort` for agentbrew model sync) |
| **Codex** | _carve-out_ | n/a — Codex is OpenAI-first (default `o3` / `gpt-5.X`); Anthropic isn't a first-class provider in `~/.codex/config.toml` | `~/.codex/config.toml` `model = "..."` (TOML top-level) | **operator** (carve-out — Codex defaults to OpenAI models; routing Codex through an Anthropic provider is out of scope for the tier-1 default) |
| **Gemini CLI** | _carve-out_ | n/a — Gemini CLI uses Gemini-family models only, not Anthropic | `~/.gemini/settings.json` | **operator** (carve-out — different model family entirely; "Opus 5.5 XHigh" doesn't translate) |
| Per-persona `ANTHROPIC_MODEL` | — | varies | minsky `personaRunner.ts` | **minsky** (pipeline override) |

**Identifier-string gotchas (these have bitten us before — verify before changing):**

- **Claude Code** rejects effort suffixes such as `-max` outright — `claude-opus-5-5-max` errors at startup. Claude Code's CLI separates the base model id from the thinking level: model = `claude-opus-5-5` (with optional `[1m]` suffix for 1M context), thinking level = `effortLevel` in `~/.claude/settings.json` (persistable values are `low`, `medium`, `high`, `xhigh`; `max` is only available in-session via `/effort max`). The `~/bin/claude` wrapper installed by `.chezmoiscripts/run_after_claude-wrapper.sh` strips any leaked `ANTHROPIC_MODEL` env var so Claude Code uses its own configured selection — don't try to pin Claude Code's model via env var, it won't take. The settings.json pin is installed by `.chezmoiscripts/run_after_claude-settings-model.sh` (idempotent `jq` merge that preserves every other key Claude Code writes — hooks, MCPs, plugins, etc.). agentbrew writes the same two keys from `Agentfile.yaml` `defaultModel`/`defaultEffort`; `tests/claude-model-agentfile-consistency.bats` keeps both sources equal.
- **Per-machine override** (an org overlay or one Mac): set chezmoi data `claude_model` / `claude_effort` in `~/.config/chezmoi/chezmoi.yaml` (kept across `chezmoi init`), or export `DOTFILES_CLAUDE_MODEL` / `DOTFILES_CLAUDE_EFFORT`. Env wins over chezmoi data, key by key. Use chezmoi data for a lasting override: the scheduled sync and doctor LaunchAgents do not read your shell env. An unset key keeps the base default. The effort must be one Claude Code can persist (`low`, `medium`, `high`, `xhigh`); any other value keeps the base default and prints a warning. `claude.model_default` asks the pin script for the resolved pair (`--print-desired`), so it follows the override. `run_after_agentbrew-sync.sh` merges the overridden keys last into the global agentbrew Agentfile (`lib/claude-model-layer.sh`, from `--print-override`), so agentbrew sync writes the same values. With no override, an overlay `Agentfile.yaml` `defaultModel` / `defaultEffort` still applies.
- **Codex** is a Cognition / OpenAI CLI — its `-c model="..."` example uses `o3` and the `--oss` flag routes through local providers (Ollama / LMStudio). Routing Codex through an Anthropic provider would require a custom `model_providers` config + an Anthropic API key + a translation layer; it's not in scope for the tier-1 "Opus 5.5 XHigh" default (`Agentfile.yaml` sets `modelOverrides.codex: null`). Codex stays at its built-in OpenAI default; the user picks the model per-invocation with `-m gpt-5.5` / `-m o3` / etc.
- **Gemini CLI** isn't installed on the M3 Max box (`command -v gemini` returns nothing). It would use Google's Gemini family natively; the Anthropic-shaped Opus tier doesn't apply. Carve-out documented; revisit if the user starts using Gemini regularly.

**Debugging:** wrong model? Check, in order:
1. For Claude Code: `cat ~/.claude/settings.json | jq '.model, .effortLevel'` → `"claude-opus-5-5"` and `"xhigh"` (or this machine's override). The fix path is `dotfiles-doctor --module claude --fix` (which sources `.chezmoiscripts/run_after_claude-settings-model.sh`) — never hand-edit settings.json, Claude Code rewrites it on shutdown.

## Claude Code env pins

`.chezmoiscripts/run_after_claude-settings-env.sh` merges `AGENT_GUARD_DEPTH_MAX=2` into the `env` object of `~/.claude/settings.json` on every apply. This lets the agent-usage-guard plugin allow nested subagents up to depth 2 instead of its default depth 1. It writes through a symlink, keeps the file mode, and refuses to touch a settings file that is not valid JSON. The doctor check `claude.env_pins` warns on drift (`dotfiles doctor --module claude --fix` repairs it). It also pins `CLAUDE_CODE_AUTO_COMPACT_WINDOW=350000`, so Claude Code compacts a conversation near 350k tokens. Without it, a 1M-context model grows past 400k, where the guard refuses tool calls that nobody can approve, and a long `/goal` run stops until someone types `/compact`. Check both with `jq .env ~/.claude/settings.json`. Test: `tests/claude-settings-env.bats`.

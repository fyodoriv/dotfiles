# Model configuration

This text moved here from `AGENTS.md` so the always-loaded file stays short. `AGENTS.md` keeps a summary and links here. The text is unchanged.

## Model Configuration

Each agent keeps its own default model. Do not infer a cross-agent model change from a change to one agent.

| Agent | Default tier | Identifier string | Config location | Owner |
|-------|--------------|-------------------|-----------------|-------|
| **Claude Code** | XHigh | `claude-opus-5-5` + `effortLevel: "xhigh"` (per-machine override below) | `~/.claude/settings.json` | **dotfiles** (`.chezmoiscripts/run_after_claude-settings-model.sh` + `modules/claude/doctor.sh` → `claude.model_default`; `Agentfile.yaml` `defaultModel`/`defaultEffort` for agentbrew model sync) |
| **Codex** | _carve-out_ | n/a — Codex is OpenAI-first (default `o3` / `gpt-5.X`); Anthropic isn't a first-class provider in `~/.codex/config.toml` | `~/.codex/config.toml` `model = "..."` (TOML top-level) | **operator** (carve-out — Codex defaults to OpenAI models; routing Codex through an Anthropic provider is out of scope for the tier-1 default) |
| **Gemini CLI** | _carve-out_ | n/a — Gemini CLI uses Gemini-family models only, not Anthropic | `~/.gemini/settings.json` | **operator** (carve-out — different model family entirely; "Opus 5.5 XHigh" doesn't translate) |
| **OpenCode** (CLI + Desktop) | per run | ordinary default stays `ollama/qwen3:14b`; goal runs pick `kimi-code-plan-global/k3.1-pro-highspeed` with `-m` or the Desktop model picker | `~/.config/opencode/opencode.json` | **agentbrew** owns the file; dotfiles never writes it. `bin/kimi-goal` passes the model per run |
| Per-persona `ANTHROPIC_MODEL` | — | varies | minsky `personaRunner.ts` | **minsky** (pipeline override) |

**Identifier-string gotchas (these have bitten us before — verify before changing):**

- **Claude Code** rejects effort suffixes such as `-max` outright — `claude-opus-5-5-max` errors at startup. Claude Code's CLI separates the base model id from the thinking level: model = `claude-opus-5-5` (with optional `[1m]` suffix for 1M context), thinking level = `effortLevel` in `~/.claude/settings.json` (persistable values are `low`, `medium`, `high`, `xhigh`; `max` is only available in-session via `/effort max`). The `~/bin/claude` wrapper installed by `.chezmoiscripts/run_after_claude-wrapper.sh` strips any leaked `ANTHROPIC_MODEL` env var so Claude Code uses its own configured selection — don't try to pin Claude Code's model via env var, it won't take. The settings.json pin is installed by `.chezmoiscripts/run_after_claude-settings-model.sh` (idempotent `jq` merge that preserves every other key Claude Code writes — hooks, MCPs, plugins, etc.). agentbrew writes the same two keys from `Agentfile.yaml` `defaultModel`/`defaultEffort`; `tests/claude-model-agentfile-consistency.bats` keeps both sources equal.
- **Per-machine override** (an org overlay or one Mac): set chezmoi data `claude_model` / `claude_effort` in `~/.config/chezmoi/chezmoi.yaml` (kept across `chezmoi init`), or export `DOTFILES_CLAUDE_MODEL` / `DOTFILES_CLAUDE_EFFORT`. Env wins over chezmoi data, key by key. Use chezmoi data for a lasting override: the scheduled sync and doctor LaunchAgents do not read your shell env. An unset key keeps the base default. The effort must be one Claude Code can persist (`low`, `medium`, `high`, `xhigh`); any other value keeps the base default and prints a warning. `claude.model_default` asks the pin script for the resolved pair (`--print-desired`), so it follows the override. `run_after_agentbrew-sync.sh` merges the overridden keys last into the global agentbrew Agentfile (`lib/claude-model-layer.sh`, from `--print-override`), so agentbrew sync writes the same values. With no override, an overlay `Agentfile.yaml` `defaultModel` / `defaultEffort` still applies.
- **Codex** is a Cognition / OpenAI CLI — its `-c model="..."` example uses `o3` and the `--oss` flag routes through local providers (Ollama / LMStudio). Routing Codex through an Anthropic provider would require a custom `model_providers` config + an Anthropic API key + a translation layer; it's not in scope for the tier-1 "Opus 5.5 XHigh" default (`Agentfile.yaml` sets `modelOverrides.codex: null`). Codex stays at its built-in OpenAI default; the user picks the model per-invocation with `-m gpt-5.5` / `-m o3` / etc.
- **Gemini CLI** isn't installed on the M3 Max box (`command -v gemini` returns nothing). It would use Google's Gemini family natively; the Anthropic-shaped Opus tier doesn't apply. Carve-out documented; revisit if the user starts using Gemini regularly.
- **OpenCode local Qwen** uses a 40,960-token context and 4,096-token output limit. Automatic compaction is off because fixed instructions and tool schemas can trigger a character-based estimate before the first answer; manual compaction remains available. A cold 31,068-token prefill exceeded 120 seconds on the M1 Max, so keep Ollama warm for the readiness budget. Three later fresh CLI sessions passed in 38, 17, and 22 seconds with no compaction.

**Debugging:** wrong model? Check, in order:
1. For Claude Code: `cat ~/.claude/settings.json | jq '.model, .effortLevel'` → `"claude-opus-5-5"` and `"xhigh"` (or this machine's override). The fix path is `dotfiles-doctor --module claude --fix` (which sources `.chezmoiscripts/run_after_claude-settings-model.sh`) — never hand-edit settings.json, Claude Code rewrites it on shutdown.

## Claude Code env pins

`.chezmoiscripts/run_after_claude-settings-env.sh` merges `AGENT_GUARD_DEPTH_MAX=2` into the `env` object of `~/.claude/settings.json` on every apply. This lets the agent-usage-guard plugin allow nested subagents up to depth 2 instead of its default depth 1. It also pins `AGENT_GUARD_AGENT_MAX=10`, the guard's limit on agents running at once on this Mac (owner choice 2026-11-06); it also pins `AGENT_GUARD_AGENT_TOKENS_MAX=25000000`, the guard's subagent token budget per window. It pins `AGENT_GUARD_LIMIT_ASK_PERCENT=95` and `AGENT_GUARD_LIMIT_DENY_PERCENT=98`: the guard starts subagents until a Claude plan window is 95% used, not its default 80%. In a `/goal` run nobody can approve its "ask", so 80% refused every subagent for hours while Claude still had 16% left (2026-11-08). In a `/goal` run the 95% ask still refuses (nobody can answer it), and the burn rule (`AGENT_GUARD_BURN_PERCENT`, 20 points) can refuse earlier. It pins `AGENT_GUARD_ROLLING_MAX=40`, the cap on agent starts per 10 minutes, instead of the default 12. The guard's "wind down" notice to the main session moves to 98% with the deny cutoff. Its other agent limits keep their defaults. It writes through a symlink, keeps the file mode, and refuses to touch a settings file that is not valid JSON. The doctor check `claude.env_pins` warns on drift (`dotfiles doctor --module claude --fix` repairs it). It also pins `CLAUDE_CODE_AUTO_COMPACT_WINDOW=350000`, so Claude Code compacts a conversation near 350k tokens. Without it, a 1M-context model grows past 400k, where the guard refuses tool calls that nobody can approve, and a long `/goal` run stops until someone types `/compact`. Check both with `jq .env ~/.claude/settings.json`. Test: `tests/claude-settings-env.bats`.

## Kimi Code plan in OpenCode

`kimi-goal` starts OpenCode in the requested directory and reports a failed OpenCode invocation to its caller.

OpenCode Desktop (cask `opencode-desktop`) and the `opencode` CLI run Kimi through the built-in `kimi-code-plan-global` provider (endpoint `https://api.kimi.ai/coding/v1`, billed to the Kimi Code membership). The desktop cask is opt-in: run `dotfiles config set opencode_desktop true` and then `dotfiles apply`. A failed optional cask install does not stop apply. agentbrew syncs the same rules, skills, commands, and MCP servers (memory included) to OpenCode as to Claude Code.

Use `oc` to open OpenCode. Version 2 uses its own authenticated shared
service; version 1 keeps the existing local attach path. On the next
`dotfiles apply`, the obsolete version 1 launch agent is removed for version 2.
The local-AI doctor checks the matching service and its API. An unrecognized
major version fails instead of guessing an interface. `oc --dir <path>` opens
a project, and `oc run --dir <path> <prompt>` runs in that project. Global
options may precede `run`. The `oc` executable also works in
noninteractive shells when the dotfiles `bin` directory is on `PATH`. It takes
precedence over another program named `oc` when that directory comes first.
The launcher and doctor prefer the managed `~/.opencode/bin/opencode` install,
then fall back to the executable on `PATH`.
If the version is unknown or macOS cannot unload the old job, apply preserves
its existing configuration and reports the failure.

1. Buy the Kimi Code plan and create a key in the Kimi Code Console. A platform API key bills per token instead.
2. Store the key: `opencode auth login` (pick Kimi Code Plan). For headless or LaunchAgent runs, also save it to the Keychain: `security add-generic-password -a "$USER" -s kimi-code-api-key -w`.
3. Check: `kimi-goal --check` (doctor line `local-ai.kimi_key`).
4. GUI: open OpenCode Desktop and pick `Kimi Code Plan / k3.1-pro-highspeed` for goal work. The ordinary model default stays local.
5. Headless goal: `kimi-goal --dir ~/apps/tooling/agentbrew --rounds 5 --auto "<goal>"`. Preview with `--dry-run`. `--auto` approves tool permissions that are not denied, so use it only for unattended runs in a worktree. `KIMI_GOAL_MODEL` overrides the highspeed default when you need a different model.
6. Remaining subscription quota: run `kimi-usage`, or type `/kimi-usage` in an agent. It reads `https://api.kimi.com/coding/v1/usages` with the same environment or Keychain credential and prints only quota fields. Weekly limits appear first when the plan reports them; reported 5-hour and monthly windows are also shown. If no weekly limit is reported, it says so instead of inventing a weekly total. Add `--forecast` to compare the current 5-hour average burn rate with the reset time. The forecast is an estimate from current usage, not a guarantee; no monthly forecast is made without a precise elapsed window.

Gaps against Claude Code: Claude Code hooks (agentbrew PreToolUse gates) do not run in OpenCode, so the git and gh wrappers in `bin/` are the only backstop.

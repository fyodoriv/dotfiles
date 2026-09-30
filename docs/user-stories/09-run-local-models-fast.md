# User Story: Run AI Coding Agents on a Local Model

> Drive an agentic coding loop against a local LLM on Apple Silicon — no internet, no per-token bill, ~85 tok/s on qwen3-coder:30b.

## Setup

```bash
# Enable AI tooling in chezmoi config:
#   use_ai_tools: true
# (see README configuration table)

# Make sure Ollama is installed + the collision-safe LaunchAgent is registered.
# If Ollama.app already owns :11434, the agent exits without starting a duplicate.
brew install ollama
launchctl bootstrap "gui/$(id -u)" \
  ~/Library/LaunchAgents/com.dotfiles.ollama.plist

# Pull the two models the local-ai stack expects:
ollama pull qwen3-coder:30b   # ~18 GB, primary
ollama pull qwen3:0.6b        # ~500 MB, small_model

# Point opencode at Ollama (one-time edit to ~/.config/opencode/opencode.json
# — set provider.ollama.options.baseURL = http://127.0.0.1:11434/v1 AND
# add "tools": true to each model entry).
```

## Verify

```bash
dotfiles doctor --module local-ai
```

Expected: every check ✓, including `local-ai.ollama_primary`, `local-ai.ollama_small`, and `local-ai.opencode_tools_enabled`.

## Manual scenario

```bash
# Two-tool-call agent run — completes in ~2 s warm:
local-ai-agent "Run pwd and date and call done"

# Larger task — write a file:
local-ai-agent --max-turns 8 \
  "Create /tmp/hello.md with a 5-line greeting. Use write_file."

# Pick the small_model for cheap loops:
local-ai-agent --model ollama/qwen3:0.6b "What is 2+2? Call done."
```

## Performance

`local-ai-bench` (Ollama 0.21.2 + the tuning in [`launchagents/com.dotfiles.ollama.plist.tmpl`](../../launchagents/com.dotfiles.ollama.plist.tmpl)) on M3 Max 64 GB:

| Call | wall_ms | prompt_eval_ms | eval_ms | eval_count | tok/s |
|------|---------|----------------|---------|------------|-------|
| 1    | ~4000   | ~295           | ~255    | 22         | ~86   |
| 2    | ~350    | ~38            | ~250    | 22         | ~86   |
| 3    | ~690    | ~38            | ~585    | 50         | ~85   |
| 4    | ~530    | ~67            | ~400    | 35         | ~87   |

Call #1's `prompt_eval_ms` is cold prefix processing. Calls #2+ stay at ~40 ms — KV cache reuse confirmed. `local-ai-bench --cold` force-unloads the model first to surface true cold-load regressions.

## Pitfalls

- **opencode silently 404s every tool call** unless each Ollama model entry in `~/.config/opencode/opencode.json` declares `"tools": true`. The `local-ai.opencode_tools_enabled` doctor check guards against drift.
- **macOS `sed -i` is not GNU `sed -i`** — `sed -i ''` (with the empty backup-suffix arg) is required. The agent's system prompt warns about this; if your tool calls fail with `sed: 1: "...": invalid command code T`, switch to `python3 -c "..."`.
- **Cold start adds ~7.5 s** on a true cold-load (model not in VRAM). `OLLAMA_KEEP_ALIVE=24h` keeps it resident, and `OLLAMA_MAX_LOADED_MODELS=2` (on 64GB+ Macs) keeps the small_model alongside so opencode's title agent doesn't evict the primary.
- **Never supervise two servers.** `bin/ollama-launchagent` probes `/api/tags` before `ollama serve`; a healthy Ollama.app owner makes the wrapper exit 0 without a retry loop.
- **Tool-call format is `tool_calls` JSON, not XML** — driven via Ollama's native `/api/chat` endpoint. opencode's OpenAI-compat path occasionally drops the tool schema's `description` field on qwen3 family models; `bin/local-ai-agent` bypasses that.

## Where the pieces live

| Path | Purpose |
|------|---------|
| [`bin/local-ai-agent`](../../bin/local-ai-agent) | Thin bash wrapper; positional task arg + `--model` / `--max-turns` / `--num-ctx` / `--keep-alive` / `--cwd` / `--quiet` |
| [`lib/local-ai-agent.py`](../../lib/local-ai-agent.py) | The agent loop — `bash`, `write_file`, `done` tools over Ollama `/api/chat` |
| [`bin/local-ai-bench`](../../bin/local-ai-bench) | 4-turn reproducible benchmark with `--cold` flag |
| [`bin/local-ai-warmup`](../../bin/local-ai-warmup) | GET-only Ollama/LM Studio/opencode health check; never launches engines or models |
| [`modules/local-ai/doctor.sh`](../../modules/local-ai/doctor.sh) | Doctor checks (engine reachable, models on disk, opencode tools:true, …) |
| [`launchagents/com.dotfiles.ollama.plist.tmpl`](../../launchagents/com.dotfiles.ollama.plist.tmpl) | Collision-safe Ollama supervisor; env-var tuning applies when it owns the server |
| [`docs/audits/local-ai-speedup-research-2026-05-11.md`](../audits/local-ai-speedup-research-2026-05-11.md) | Research brief on speculative decoding, MLX, KV cache, etc. |

For background on the recurring local-agent failure modes (and the fixes shipped into `lib/local-ai-agent.py` after each one) see [`docs/audits/local-ai-task-runs-2026-05-11.md`](../audits/local-ai-task-runs-2026-05-11.md).

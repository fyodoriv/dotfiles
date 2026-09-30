# Local-AI Speed-up Research — 2026-05-11

Captures the 7-angle research run done after the first speed-up landing
(PR #9) so future operators don't re-research the same upstream gaps.

**Hardware:** M3 Max, 64 GB unified memory, Rosetta-mode shell
(`uname -m == x86_64`).

**Stack baseline (after PR #9):**
- Ollama 0.21.2 with `OLLAMA_KV_CACHE_TYPE=q8_0`, `OLLAMA_FLASH_ATTENTION=1`,
  `OLLAMA_CONTEXT_LENGTH=32768`, `OLLAMA_KEEP_ALIVE=24h`,
  `OLLAMA_MAX_LOADED_MODELS=2`.
- `qwen3-coder:30b` (MoE, 30B total / 3.3B active, q4_K_M).
- `bin/local-ai-agent` using directive system prompt + `/api/chat` (not the
  OpenAI-compat path that opencode uses internally).
- Measured cold load 7.5 s, warm 3-token reply 215 ms, realistic 2-bash-call
  agent turn 1.6 s, output 85 tok/s.

## 1. Speculative decoding (Ollama)

**Verdict: not viable today.**

- [Ollama PR #8134](https://github.com/ollama/ollama/pull/8134) (Jan 2025)
  added llama.cpp's draft-model speculative decoding — closed without merge
  by maintainer @pdevine because it conflicted with the engine rewrite.
- A user benchmark in that PR thread (April 2025) showed
  **llama.cpp draft = 39.69 tok/s vs Ollama no-draft = 29.75 tok/s on
  Qwen2.5-Coder-32B** (~33% speedup if it ever lands).
- [Ollama PR #15980](https://github.com/ollama/ollama/pull/15980) (May 2026)
  shipped multi-token-prediction (MTP) speculative decoding **for Gemma 4
  only** — no qwen3-coder path.

Tracked as `track-ollama-speculative-decoding-pr` in TASKS.md so we pick
this up the moment a follow-up PR lands.

## 2. MLX vs llama.cpp (Ollama's backend) on Apple Silicon

**Verdict: not worth switching for our 30B MoE.**

- Qwen3-Coder-Next on M1 Max (similar profile) via oMLX 0.3.0:
  **48.7 tok/s prefill, 36.7 tok/s generation** at 16K context (4-bit).
- Qwen3.5-35B-A3B (similar profile, famstack.dev benchmark, M3 Max):
  - LM Studio GGUF: **41.7 tok/s**
  - oMLX: **38.0 tok/s** (-8.2% vs GGUF)
  - Ollama GGUF: **26.0 tok/s** (-37% vs LM Studio, same engine!)
- Smaller models favor MLX (Gemma 3n 4B: MLX 44 tok/s vs GGUF 35 tok/s,
  +25%). At 30B+, the unified-memory bandwidth ceiling dominates and the
  engine choice barely matters.
- mlx-lm server tool_calls support is incomplete: [PR #607](https://github.com/ml-explore/mlx-examples/pull/607)
  shows the server crashing on non-JSON tool payloads, and qwen3-coder's
  format is a likely victim.

**The interesting number is the 37% Ollama → LM Studio gap on the same
GGUF.** That's our biggest theoretical win and is tracked as
`bench-ollama-vs-llamacpp-wrapper-overhead` in TASKS.md.

## 3. KV cache reuse across requests

**Verdict: ALREADY WORKING on our setup. Confirmed by measurement.**

`bin/local-ai-bench` output on the warm path:

```
 #   wall_ms  prompt_eval_ms   eval_ms  eval_count    tok/s
──  ────────  ──────────────  ────────  ──────────  ───────
 1       404              50       255          22       86
 2       346              37       250          22       88
 3       688              37       583          50       86
 4       529              66       400          35       87
```

Call #1 prompt_eval = 50 ms (already warm from earlier traffic). Calls
#2-4 stay at 37-66 ms — only the small user-message delta is processed;
the 287-token system + tools prefix is reused. After a forced unload
(`--cold` flag), call #1 climbs to 295 ms and calls #2+ drop right back
to 37 ms.

Mechanism: [Ollama PR #6735](https://github.com/ollama/ollama/pull/6735)
+ [PR #2186](https://github.com/ollama/ollama/pull/2186). Exact-prefix
token match across requests as long as the model is loaded — which
`OLLAMA_KEEP_ALIVE=24h` ensures.

## 4. Smaller / faster coder models

**Verdict: don't switch unless you need >100 tok/s for non-agentic work.**

| Model | Size (active) | Apple Silicon tok/s | Agentic quality |
|-------|---------------|--------------------|-|
| **qwen3-coder:30b** (current) | 30B (3.3B) MoE | 36-49 | high (SWE-Bench optimized) |
| Qwen2.5-Coder-32B | 32B dense | 8.5-10.9 | very high (92.7% HumanEval) but slow |
| DeepSeek-Coder-V2.5-Lite | 16B (2.4B) MoE | ~23 (M4 Pro) | lower (60 MMLU) |
| Codestral-2501 | 22B dense | no local M3 number | high (86.6%) — try if needed |
| Granite-Code-8B | 8B dense | 50-60 | ~70% HumanEval; good for long-context non-agent tasks |
| Granite-Code-3B | 3B dense | 100+ | ~60% HumanEval; non-agentic only |

For agentic coding work, qwen3-coder:30b is on the Pareto frontier.

## 5. Structured output / constrained decoding

**Verdict: incompatible with qwen3-coder's tool format. Skip.**

- [Ollama PR #7900](https://github.com/ollama/ollama/pull/7900) (Dec 2024)
  added JSON-schema → GBNF grammar constrained decoding via the
  `format: { ... }` request field. Usually no slowdown; sometimes faster.
- [Ollama issue #8095](https://github.com/ollama/ollama/issues/8095)
  (unfixed): combining structured output with tool calls yields an empty
  `tool_calls` array — the schema constraint suppresses them.
- [Ollama PR #12248](https://github.com/ollama/ollama/pull/12248)
  (Sept 2025) added a custom Go renderer/parser for qwen3-coder; its tool
  format is *not* JSON, so schema-constrained generation doesn't help.

Use native `tool_calls` (already optimized).

## 6. Batching multiple small calls

**Verdict: Ollama has concurrency, not batching. Use `asyncio.gather` if
you want N parallel calls.**

- `OLLAMA_NUM_PARALLEL` runs N independent forward passes with separate
  KV cache slots — not true batching.
- [Ollama issue #10699](https://github.com/ollama/ollama/issues/10699)
  (open) requests real batching; maintainer hasn't engaged.
- For our use case (session title + main response) we're already pinned
  at `OLLAMA_NUM_PARALLEL=1` because we don't want contention. Bumping it
  to 2 would let opencode's title agent run in parallel with the main
  build agent, saving ~500ms per session start.

## 7. Other 2026 developments

**Apple Neural Engine (ANE):** Not relevant for 30B-class LLMs. Draw Things
1.20260410 added ANE for 8-bit models (~1.8× on M4); on M3 the speedup
disappears, and no Ollama / llama.cpp / MLX integration exists.

**Ollama 0.21 changelog:**
- v0.21.0 (April 2026): Gemma 4 MLX, mixed-precision quantization, new
  ops (Conv2d, Pad, activations, RoPE-with-freqs).
- v0.21.1 (May 2026): fused top-P/top-K, faster tokenization, GLM4-MoE
  Lite router-head fusion.
- No qwen3-coder-specific optimizations in this stream.

**GGUF vs MLX file format:** At 30B+ the format doesn't matter — both hit
the unified-memory bandwidth wall (~273 GB/s on M4 Pro, similar on M3
Max) at ~16 tok/s for dense 27B at 4-bit. The runtime wrapper overhead
dominates (Ollama vs LM Studio gap, see §2).

## Prioritised next 30 minutes

1. **`bench-ollama-vs-llamacpp-wrapper-overhead`** — clone llama.cpp,
   run llama-server against the same GGUF blob Ollama has on disk, bench
   side-by-side. If >15% faster, propose a thin OpenAI-compat wrapper
   around llama-server as the local-ai default.

2. **`docs-local-ai-tuning-user-story`** — capture the working recipe
   (Ollama env vars, `tools: true` opencode gotcha, BSD-vs-GNU sed quirk,
   the bench + agent scripts) as `docs/user-stories/09-run-local-models-fast.md`
   so the next person doesn't re-research.

## Not worth doing (research findings)

- MLX for 30B-class models on this hardware (-8% vs GGUF).
- Smaller coder models (we lose agentic quality for marginal speed).
- Structured output (incompatible with qwen3-coder tool format).
- ANE (no integration; no measurable speedup on M3).
- Speculative decoding (upstream-blocked; track only).

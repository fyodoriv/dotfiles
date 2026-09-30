# Local-AI Upstream Roadmap

This is a watch-list of upstream Ollama PRs/issues that may impact our local-AI stack. Check this list monthly. When a relevant upstream change lands, file a follow-up task in dotfiles TASKS.md to enable the feature.

## Overnight grind run modes (in progress)

`local-ai-loop --queue tasks-queue/` reads one-task-per-file specs (TASKS.md
block format; one task per file is the v1 contract, a `## P*` header is
optional) in lexical filename order instead of the repo TASKS.md, and deletes
a spec only after the full close gates (make check + the pre-merge reviewer)
pass — failures leave the spec for the next run. Remaining epic slices:
per-task summary CSV (`overnight-grind-summary-csv`) and per-task dogfood
branches with merge-or-revert (`overnight-grind-branch-per-task`).

## Speculative decoding

- [Ollama PR #8134](https://github.com/ollama/ollama/pull/8134) (closed, Jan 2025): Initial speculative decoding implementation, but only for Gemma 4.
- [Ollama PR #15980](https://github.com/ollama/ollama/pull/15980) (May 2026): Adds speculative decoding for Gemma 4 only. If qwen3-coder support lands, expect ~33% speedup.

## MLX support for qwen3-coder

Current MLX paths in Ollama 0.21 only cover Gemma 4. Track when qwen3-coder MLX support lands.

## qwen3-coder XML tool-call parser crash (our 3-stage retry ladder)

- [Ollama Issue #14834](https://github.com/ollama/ollama/issues/14834) (open as of 2026-06-12): "qwen tool call parsing failed … unexpected EOF" — the crash `lib/local-ai-agent.py`'s retry ladder works around.
- [Ollama PR #14906](https://github.com/ollama/ollama/pull/14906) (closed UNMERGED 2026-06-12): first attempt to treat unparseable qwen tool calls as content.
- [Ollama PR #14915](https://github.com/ollama/ollama/pull/14915) (open): successor with the same approach. When this (or equivalent) merges into a tagged release, simplify the retry ladder per TASKS.md `track-ollama-qwen3coder-parser-fix`.

## Constrained / structured tool-call decoding

- [Ollama Issue #8095](https://github.com/ollama/ollama/issues/8095) (open): Combining structured output with tool calls yields an empty `tool_calls` array — the schema constraint suppresses them. Watch for a fix.

## True batching API

- [Ollama Issue #10699](https://github.com/ollama/ollama/issues/10699) (open): Currently only concurrency, not true batching. Requesting real batching support.

## How to check the watch list

```bash
# `gh` does not accept multiple positional ids — fetch one at a time.
for n in 8134 15980 14906 14915; do
  gh pr view "$n" --repo ollama/ollama --json state,title,updatedAt
done
for n in 8095 10699 14834; do
  gh issue view "$n" --repo ollama/ollama --json state,title,updatedAt
done
# No github.com gh auth on this host? The anonymous API works too:
#   curl -sf https://api.github.com/repos/ollama/ollama/pulls/14915 | jq '{state, merged}'
```
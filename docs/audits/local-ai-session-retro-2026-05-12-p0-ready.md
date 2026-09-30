# P0-ready loop achieved (2026-05-12)

## Goal

User: "keep working in a loop improving local models and their setup
(and merging everything) until local models are able to deliver a P0
task reliably."

## Result

**3 out of 3 P0 tasks completed autonomously, end-to-end, by
`qwen3-coder:30b` via `bin/local-ai-loop` — 6 PRs merged this session.**

| PR | Name | Shipped |
|----|------|---------|
| #21 | 4 capability upgrades (retry ladder, patch_file, preload, turn budget) | O/P/Q/R |
| #22 | critic @test count-check | V |
| #23 | critic fallback + procedural-literal filter | W |
| #24 | **ROOT-CAUSE FIX**: multi-line TASKS.md parser | X |
| #25 | first autonomous P0 (readiness-check, 5 turns, 18.0s) | Y |
| #26 | 3rd P0 (warmup, 16 turns with reality reconciliation) | Z |

## P0 telemetry scoreboard

| # | Task | Turns | Time | @test count | Quality |
|---|------|-------|------|-------------|---------|
| 1 | cover-local-ai-readiness-check-surface | **5** | **18.0s** | 3/3 spec match | ✓ |
| 2 | cover-local-ai-record-lesson-surface | **5** | **18.5s** | 3/3 spec match | ✓ |
| 3 | cover-local-ai-warmup-surface | **16** | **100.5s** | 4/4 spec match (with reality reconciliation) | ✓ |

Average: 8.7 turns, 45.7s. qwen3-coder:30b on M3 Max 64GB.

## The ROOT CAUSE that unlocked everything

After 9 P0 dogfood attempts with "make check passes" auto-closes but
weak deliverables (1-2 tests instead of 3), we traced it to a 2-year-
old bug in `lib/local-ai-loop.py`'s `TASK_META` regex:

```python
TASK_META = re.compile(r"^\s+-\s+\*\*(?P<key>[A-Za-z]+)\*\*:\s*(?P<val>.+)$")
```

This only captured **the first line** of each metadata bullet. A real
task's `**Details**:` section spans 4-6 lines; the crucial "3 @test
cases" sentence lived on line 3 and was being silently dropped before
the agent ever saw the prompt. Every guard we added to the critic
(count-check, anchor-check, fallback) was a no-op because the
requirement never reached the agent's context.

Fix: continuation-line parser that reads ANY indented line that
isn't itself a meta bullet or section header. With that in place,
the agent's task_desc grew from 803B → 1382B+, the count-check saw
"3 @test cases", and the first autonomous P0 landed in the next
attempt.

## What reliably works now

**Agent tools:**
- `bash` (with kill/HOME-write deny-list)
- `write_file` (atomic, refuses destructive overwrites)
- `patch_file` (replace / insert_after / append — single-match enforcement)
- `verify_cli_claims` (catches hallucinated CLI flags in docs)
- `critique_test` (catches placeholder / tautology / missing-anchor tests)
- `done` (gated on `make check` passing + all bats tests critiqued)

**Loop driver:**
- Multi-line TASKS.md parser ✓
- File preload from `**Files**:` field ✓
- Complexity-scaled turn budget (14-28 turns)
- Per-task cleanup on failure (revert tracked + delete untracked in
  safe prefixes, preserving the telemetry CSV)
- Telemetry CSV at `docs/audits/local-ai-runs.csv` accumulates

**Safety:**
- 27 failure modes documented in `docs/audits/local-ai-failure-modes.md`
- Loaded into the agent system prompt at every run
- 90+ bats tests pinning every invariant

## How to use it

```bash
cd ~/apps/dotfiles
./bin/local-ai-loop --max-tasks 3 --deadline 30m
# or for a single experiment:
./bin/local-ai-agent --max-turns 14 --telemetry "write tests/foo.bats with 3 @test cases that ..."
```

Trend analysis:

```bash
# P0 success rate
awk -F, '/priority P0/ && NR>1 {n++; if($3=="done") g++} END{printf "%d/%d\n", g, n}' \
  docs/audits/local-ai-runs.csv
```

## What's next

The loop now handles **narrow, spec-complete bats-surface tasks**
reliably. The next class of task is genuine feature work — a test
that exercises runtime behavior, or a small function added to
`lib/*.sh`. That needs `patch_file` to see real use, which it hasn't
yet. Worth another iteration campaign.

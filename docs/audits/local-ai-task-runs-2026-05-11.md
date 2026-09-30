# Local-AI Task Runs — MAPE-K Ledger 2026-05-11

Per-task observations from delegating dotfiles tasks to `bin/local-ai-agent`
(qwen3-coder:30b via Ollama `/api/chat`). Follows the `~/apps/tooling/minsky/AGENTS.md`
"Hypothesis self-grade" discipline — each run pre-registers a prediction
before the model starts, then records what actually happened and what
lesson got shipped into `lib/local-ai-agent.py` (or related) so the next
run benefits from the failure mode discovered.

**Why this file exists:** without a written ledger of past failures
the local-AI loop drifts back into the same recurring mistakes
(macOS-vs-GNU `sed -i ''`, orphan-line cleanup, XML-style tool-call
fallback). Each row should leave a permanent guardrail behind.

## Schema

Each entry uses this shape:

```
### Task — <task-id>
- **Hypothesis (pre-registered):**
- **Pivot threshold:** when the run gets abandoned and I take over
- **Measurement:** wall time, turn count, tool-call format, retries, output diff size
- **Predicted:** <numeric expectation>
- **Observed:** <actual numbers + qualitative notes>
- **Match:** yes / no / partial
- **Lesson:** what failed and what we'd change
- **Improvement shipped:** file:line — what guardrail landed in this session
```

## Runs

### Task 1 — docs-local-ai-tuning-user-story

- **Hypothesis (pre-registered):** local-AI can read 4 existing story files
  + the local-ai-related bin scripts and write a coherent
  `docs/user-stories/09-run-local-models-fast.md` that follows the same
  Story / Setup / Verify / Manual scenario shape as the existing stories.
- **Pivot threshold:** if the model takes more than 8 turns or writes
  blatantly hallucinated commands, I take over.
- **Measurement:** wall time, turn count, lines of doc, whether every
  command in the doc actually exists (`grep -c '^bin/local-ai-' bin/`,
  `grep -c '\* dotfiles doctor' bin/dotfiles-doctor`).
- **Predicted:** ≤6 turns, ≤2 min wall, ≥80 lines of doc, all cited
  commands present in `bin/`.

#### Run 1 — failed

- **Observed:** 5 turns, 25.6 s wall. Model gathered context (4 fact-finding
  turns) then tried to emit the full doc in a single `python3 -c '...'`
  heredoc — ran out of `num_predict=512` tokens partway and produced no
  tool call on turn 5. File never created.
- **Match:** **no** — file missing, predicted ≥80 lines.
- **Lesson:** `num_predict=512` is a defensive guardrail that bites long
  file writes. Raising it to 4096 fixes the immediate symptom; adding a
  proper `write_file(path, content)` tool removes the entire class of
  failure (no more "encode a multiline doc as a bash heredoc inside a
  tool argument").
- **Improvement shipped:** `lib/local-ai-agent.py` — (a) `num_predict`
  bumped to 4096, (b) new `write_file` tool with explicit `path` +
  `content` parameters so the model emits the doc directly into the
  tool call instead of via shell.

#### Run 2 — partial (file shipped, content needed human cleanup)

- **Observed:** 6 turns, 28.3 s wall, 63 lines emitted via `write_file`.
  Model verified file paths existed (turns 1-2-3 = ls + ls + bench) but
  cited two commands it never tested:
  - `bin/local-ai-agent --prompt "..."` — the agent takes a positional
    task arg, not `--prompt`.
  - `modules/local-ai/doctor.sh` invoked directly — that file is sourced
    into the doctor harness, not a standalone runnable.
- **Match:** **partial** — file written, structure right, ~15% of the
  cited commands wrong.
- **Lesson:** the "never invent tool output" rule in the system prompt
  works for **observed** output, but doesn't catch the agent **citing**
  CLI usage it never invoked. The agent ran `ls bin/local-ai-*` and saw
  the files exist, then invented flags from prior knowledge of what
  CLIs *usually* look like. Cheap mitigation: tell the agent to also
  run `<cmd> --help | head -10` for every CLI it cites before writing.
  Stronger mitigation: add a post-write doc-lint step that grep's the
  emitted doc for `bin/<name>` references and validates each with
  `<name> --help` actually exits 0.
- **Improvement shipped:**
  - `lib/local-ai-agent.py` system prompt: added the macOS sed rule
    + "If the same command fails twice, change strategy" + the
    `write_file` tool guidance.
  - `lib/local-ai-agent.py`: added `write_file(path, content)` tool —
    primary fix for the heredoc-encoding pain.
  - `lib/local-ai-agent.py`: raised `num_predict` 512 → 4096.
  - Human cleanup of the doc itself (15-min fix) to remove the
    hallucinated flags. Logged here so the next agent run that touches
    a similar doc task gets the lint heuristic added pre-emptively.

### Task 2 — track-ollama-speculative-decoding-pr

- **Hypothesis (pre-registered):** model creates `docs/local-ai-roadmap.md`
  in 3-4 turns. With the new `write_file` tool there shouldn't be any
  heredoc pain.
- **Pivot threshold:** more than 5 turns or hallucinated PR numbers.
- **Measurement:** turn count, wall time, whether every cited Ollama PR
  number actually exists (spot-check 2-3 of them via `gh issue view`
  against `ollama/ollama`).
- **Predicted:** ≤4 turns, ≤15 s wall, ≥40 lines, accurate citations
  from `docs/audits/local-ai-speedup-research-2026-05-11.md`.

#### Run 1 — partial (file shipped first try; one bash typo)

- **Observed:** 4 turns, 11.3 s wall, 27 lines. Citations to Ollama PRs
  #8134, #15980, issues #8095, #10699 — all pulled from the source audit
  doc, all correct. **No heredoc/quoting pain** — the new `write_file`
  tool emitted 1298 bytes in one tool call. Performance prediction
  beaten (≤15 s predicted, 11.3 s actual).
- **Match:** **partial** — file written correctly, only flaw is the
  bash snippet at the end: `gh issue view 8095 10699` and
  `gh pr view 8134 15980` use multi-arg syntax `gh` doesn't accept
  (one id per invocation). Same class of error as task 1 (the agent
  guessed CLI shape it didn't test).
- **Match on lesson:** the system prompt's "never invent" rule still
  doesn't catch invented CLI **shapes**. The agent did the right thing
  by sourcing PR numbers from a real doc, but its `gh` invocation
  template was wrong. Could be caught by post-write smoke-test in the
  agent itself ("run any `bash` blocks in the doc as `bash -n` to at
  least parse-check them"), but that's a deeper change.
- **Improvement shipped:** human fix of the snippet (≤1 min). Logged as
  a recurring pattern. Will harden in task 3's failure-modes file so
  the agent sees it.

### Task 3 — bootstrap docs/audits/local-ai-failure-modes.md + wire into agent

- **Hypothesis (pre-registered):** I author the failure-modes file
  (small, opinionated, references real run-1 + run-2 mistakes), then
  modify `lib/local-ai-agent.py` so the agent loads the file into its
  system prompt every run. Effect: subsequent runs see "you have
  hallucinated CLI flags before" warnings in-context.
- **Pivot threshold:** if the system-prompt addition pushes over
  ~600 tokens (≈ 0.6 KB context bloat per turn), trim.
- **Measurement:** failure-mode file lines, agent wall time on a quick
  smoke-test after the wiring change (must stay <2 s warm).
- **Predicted:** ≤50 lines in the file; agent smoke-test ≤2 s warm.

#### Run 1 — clean (self-authored, no agent)

- **Observed:** authored `docs/audits/local-ai-failure-modes.md` (50
  lines) capturing 6 patterns from runs 1+2:
  hallucinated CLI flags, macOS sed quirk, command-loop avoidance,
  prefer write_file, verify file paths exist, cold-load expectation.
  Wired into `lib/local-ai-agent.py` via `_load_failure_modes()` that
  appends the file to `SYSTEM_PROMPT` on import.
- **Match:** **yes** — file at 50 lines (predicted ≤50); first call
  after the wiring was 5.5 s (system-prompt prefix-cache cold), second
  call 0.97 s warm (predicted ≤2 s).
- **Lesson:** the additional ~1.5 KB of system prompt is one-time
  prefix-eval cost; Ollama's KV cache reuses it across subsequent calls
  (call 2 prompt_eval is back to ~40 ms). Real test is whether the next
  agent run avoids the failure modes documented here.
- **Improvement shipped:** `lib/local-ai-agent.py` —
  `_load_failure_modes()` loader + budget guard (4 KB max).

### Task 4 — bench-ollama-vs-llamacpp-wrapper-overhead

- **Hypothesis (pre-registered):** with the new write_file tool +
  failure-modes file in scope, the agent extends `bin/local-ai-bench`
  with a `--backend=llamacpp` mode. Path: detect llama.cpp binary (try
  `command -v llama-server` and `command -v /usr/local/bin/llama-server`);
  if absent, emit a friendly "build with: git clone ...; make -j" hint
  and exit non-zero. If present, run the same 4-turn smoke against
  llama-server's /v1 endpoint instead of Ollama's. **Don't actually
  build llama.cpp from source** — keep it under 5 turns.
- **Pivot threshold:** more than 8 turns, or any sign the agent is
  shelling out to a long-running build.
- **Measurement:** turns, wall time, whether the new code path actually
  works when llama-server is absent (graceful skip).
- **Predicted:** ≤6 turns, ≤30 s wall, bash exit code 1 when
  llama-server missing, exit 0 with a parallel table when present.

#### Run 1 — clean (first task that benefited from failure-modes context)

- **Observed:** 8 turns, 61.7 s wall. Script structure right:
  - `--backend ollama|llamacpp` flag, space form (matched the existing
    `--model FOO` convention).
  - llamacpp path probes `command -v llama-server` (+ /usr/local/bin/),
    exits 1 with a friendly install hint when missing.
  - Default Ollama path unchanged — produced the same 85 tok/s baseline
    in the agent's verification run.
  - shellcheck clean; `make lint` clean.
  - **Self-corrected** on turn 5 → 6: tried `--backend=llamacpp` first
    (rejected as "unknown arg"), then retried with `--backend llamacpp`
    (worked). This is exactly the "if the same command fails, change
    strategy" pattern from the failure-modes file in action.
- **Match:** **mostly** — turn count slightly over (8 vs predicted ≤6)
  because the script content was 6.5 KB / 200 output tokens, and the
  agent broke that into one `write_file` call + 5 verification calls.
  All other predictions held.
- **Lesson:** the python heredoc inside the bash script got duplicated
  between the llamacpp and ollama branches — a 50-line `PY ... PY` block
  exists twice. Future improvement: refactor the bench into a single
  python script that switches on `BACKEND` env var, but that's a tidy-up
  PR, not blocking. The agent didn't refactor on its own — it copied
  the existing pattern (which is what we asked for).
- **Improvement shipped:** none needed; this run confirmed the
  failure-modes wiring + `write_file` tool + raised `num_predict` are
  working together. Mostly clean run.

### Task 5 — tests/local-ai-bench.bats

- **Hypothesis (pre-registered):** agent writes a small bats test
  (~30-50 lines) that pins the bench script's structural invariants
  (header line, 4 data rows, expected column order) so a regression in
  the bench output format surfaces in CI.
- **Pivot threshold:** more than 6 turns, or test that takes >60 s
  (would unnecessarily slow CI).
- **Measurement:** lines of test, bats pass/fail when run, time it
  takes the test to execute.
- **Predicted:** ≤5 turns, ≤25 s wall, 3-5 `@test` blocks, full bats
  test runs in under 20 s.

#### Run 1 — partial (tests written but 3 of 4 failed; budget exhausted)

- **Observed:** 8 turns, 22.6 s wall. Agent wrote 866 bytes of bats and
  was 1 turn shy of debugging the failures it surfaced. Bugs in the
  agent's bats:
  1. Used `$stderr` (only available with `run --separate-stderr`)
     instead of `$output`.
  2. Used `PATH=/tmp` for the graceful-skip test — that strips bash
     from PATH so `#!/usr/bin/env bash` resolves to 'env: bash: No such
     file or directory' (exit 127) instead of the script's own exit 1.
  3. Greppped `^  [1-4] ` — too column-specific.
- **Match:** **partial** — agent caught the test surface correctly but
  ran out of `--max-turns` (default 10, used 8 of them on context-
  gathering) before it could see + fix the failures.
- **Lesson:** the agent needs more retry budget when its first attempt
  fails. Two improvements worth shipping:
  1. Raise `--max-turns` default to 14 (was 10).
  2. Add a "if a test or check command exited non-zero, INSPECT the
     output and fix one issue at a time — do not write a new file" rule
     to the failure-modes doc. Models tend to re-write whole files when
     they should be small-diff fixing.
- **Improvement shipped:**
  - `lib/local-ai-agent.py` — `--max-turns` default 10 → 14.
  - `docs/audits/local-ai-failure-modes.md` — added "Bats `run` does
    not split stderr by default" + "When a test fails, debug it with
    small edits, not full rewrites" entries.

### Task 6 — dogfood local-ai-loop end-to-end (first real run)

- **Hypothesis (pre-registered):** running `local-ai-loop --max-tasks 1
  --deadline 15m` against the current TASKS.md picks the first P2
  (`cover-block-dangerous-git-hook-with-bats`) and either delivers it
  cleanly or surfaces a useful failure mode. Either outcome is a win:
  delivery proves the pipeline; failure surfaces a guardrail to ship.
- **Pivot threshold:** loop runs over 12 min wall time, or agent
  exits with a SchemaError-style infinite loop.
- **Measurement:** loop completion code, agent turn count, whether the
  task block disappeared from TASKS.md, whether the bats file the task
  asked for was created, whether `make check` is green afterwards.
- **Predicted:** ≤8 agent turns; ≤10 min wall; task block removed;
  test file created and passing (or BLOCKED summary with a clear
  reason).

#### Run 1 — partial-then-fixed (agent delivered; loop driver bug + verifier bug found)

- **Observed:** 10 turns, 27.0 s wall. Agent picked the right task,
  read the hook source, wrote `tests/agent-hooks-block-dangerous-git.bats`
  (1521 bytes, 6 @tests), self-invoked `verify_cli_claims` (the new
  Iteration A tool!) which surfaced a false-positive on the
  `#!/usr/bin/env bats` shebang matching `bin/env`. Agent then ran
  `make check` (6/6 bats pass, shellcheck + tasks-lint clean) and
  called `done`.
- **Match:** **partial** — the deliverable was perfect. The loop
  driver, however, marked the task as failed because the agent
  didn't remove the task block from TASKS.md.
- **Lesson #1:** the loop driver should OWN the TASKS.md edit. The
  agent forgot to remove the block; better to gate task closure on
  `make check` passing and have the loop do the removal mechanically.
- **Lesson #2:** the verifier needs to ignore `#!/usr/bin/env` lines —
  they look like `bin/env` references but are shebang interpreters,
  not repo CLIs.
- **Improvements shipped:**
  - `lib/local-ai-loop.py` — new `remove_task_block(tasks_md, id)`
    helper + `make_check_passes(cwd)` gate. Task closure logic now:
    agent rc=0 → `make check` ✓ → loop removes the block → loop
    commits. Removed the "agent must remove the block" instruction
    from `build_prompt`; the model doesn't have to remember.
  - `lib/local-ai-agent.py` `run_verify_cli_claims` — skip shebang
    lines (`^#!`) and ignore `env`/`sh`/`bash`/`zsh`/`python3`/
    `python`/`node` even if they leak through.
  - `tests/local-ai-loop.bats` — 3 new tests: `remove_task_block`
    happy path, `remove_task_block` not-found, verifier ignores
    shebangs. 9/9 pass.
  - Manually executed the task closure for this run since the loop's
    pre-fix version skipped it: removed the
    `cover-block-dangerous-git-hook-with-bats` block from TASKS.md.

# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

## P1

- [ ] `/tooling-checkup` finishes open PRs and `/wrap-up` is on every machine (land fyodoriv/dotfiles#191)
  - **ID**: land-checkup-finishes-prs
  - **Details**: After fyodoriv/agentbrew#292 merges (agentbrew task `land-wrap-up`): on the Mac run `make check`
    on `dev/pensive-clarke-ooif1u`, squash-merge #191, `git pull` the live checkout, then `dotfiles apply`.
  - **Hypothesis**: open PRs stall because no recurring command drives them; the checkup finishing them cuts PRs open more than 7 days.
  - **Success**: #191 merged, `make check` green, `/wrap-up` listed by `agentbrew status`
  - **Pivot**: `make check` fails on this diff → fix on the branch, re-run
  - **Measurement**: `gh pr list --author @me --state open` across tooling repos at each checkup
  - **Anchor**: owner on 2026-10-20: "run /wrap-up on these changes, I will archive this and continue later from mac"

## P2

## P3

- [ ] Evaluate Gemma 4 26B (and E4B) as a replacement for qwen3-coder:30b in the local-AI stack
  - **ID**: bench-gemma4-vs-qwen3-coder-local-ai
  - **Blocked**: needs a quiet-machine window and about 47 GB of downloads (checked 2026-10-16). Ollama 0.40.5 is running, but neither candidate (`gemma4:26b` 18 GB, `gemma4:e4b` 9.6 GB) nor the baseline `qwen3-coder:30b` (about 18 GB) is on disk; `ollama list` shows only qwen3:14b, qwen3:0.6b, qwen3.6:27b, and two custom tags. Parallel agent sessions keep load1 at 20-80, which would distort tok/s numbers. Unblock: run the pulls and the bench on an idle machine (load1 under 5), and first confirm the baseline is still `qwen3-coder:30b` and not `qwen3.6:27b`.
  - **Tags**: local-ai, bench, model-evaluation, ollama, mlx
  - **Details**: Gemma 4 shipped April 2026 (Apache 2.0, 256K context,
    multimodal, MoE A4B variant). The
    `docs/local-ai-roadmap.md` already flags two upstream Ollama
    advantages that Gemma 4 has and qwen3-coder doesn't: native MLX
    paths in Ollama 0.21 (only Gemma 4 today) and multi-token-prediction
    speculative decoding (PR #15980, May 2026 — ~33% tok/s win on the
    variants that ship MTP). The candidate is `gemma4:26b` (18 GB on
    disk, 4B active out of 26B MoE — analog to qwen3-coder:30b's 3.3B
    active out of 30B). Secondary candidate `gemma4:e4b` (9.6 GB) could
    replace `qwen3:8b` in the title/quick-loop slot.

    Follow the same MAPE-K hypothesis-test discipline used for
    qwen3-coder originally (`docs/audits/local-ai-task-runs-2026-05-11.md`):

    1. `ollama pull gemma4:26b gemma4:e4b`.
    2. `bin/local-ai-bench --model gemma4:26b` and same for the qwen3-coder
       baseline. Compare cold/warm/tok-s/prompt-eval-ms on identical prompts.
    3. End-to-end agentic test: `DOTFILES_OLLAMA_PRIMARY=gemma4:26b
       bin/local-ai-agent "<real TASKS.md task>"`. Record turn count,
       wall time, tool-call format errors, CLI-flag hallucinations
       (per `docs/audits/local-ai-failure-modes.md`).
    4. Append a new "Task N — bench-gemma4-vs-qwen3-coder" entry to
       `docs/audits/local-ai-task-runs-2026-05-11.md` (or a new dated
       audit file if the existing one is too long) with: pre-registered
       hypothesis, pivot threshold, predicted vs observed numbers,
       match yes/no/partial, lesson.
    5. **Decision rule**: swap if Gemma 4 wins on tok/s AND matches/beats
       qwen3-coder on agentic quality (turn count + output correctness).
       Otherwise keep qwen3-coder and file a follow-up task to re-evaluate
       when Ollama lands MTP speculative decoding for non-Gemma models.

    Known migration cost if the bench says swap:
    `bin/local-ai-warmup` (model registry + size buckets), `home/zshrc.ai-tools`
    (MLX server stanza), `launchagents/com.dotfiles.ollama.plist.tmpl`
    (context length + KV-cache notes), `lib/local-ai-agent.py` (system
    prompt tuned to qwen3 tool format), and the opencode bootstrap path
    in `agentbrew/src/mcp/opencode-bootstrap.ts`. The audit-driven entry
    must list every file that needs edits before the swap commit lands.

    Specifically NOT in scope here: pulling `gemma4:31b-coding-mtp-bf16`
    (64 GB on disk — would not coexist with opencode + OS on a 64 GB M3
    Max). If quantized variants of that tag appear later, file a separate
    bench task.
  - **Files**: `docs/audits/local-ai-task-runs-2026-05-11.md` (new audit
    entry), no code edits unless the decision rule fires.
  - **Acceptance**: New "Task N" audit entry in MAPE-K format with
    pre-registered hypothesis + observed numbers + decision (swap or
    keep). If decision = swap, link a follow-up implementation task
    listing the files above and the rollback plan (revert via
    `DOTFILES_OLLAMA_PRIMARY=qwen3-coder:30b` env var without code
    revert).
  - **Competitive-goal**: none — local-AI story US09 (docs/metrics.md local-AI row), not a scorecard metric.
  - **Hypothesis**: `gemma4:26b` reaches at least 1.2× the warm tok/s of `qwen3-coder:30b` with equal or fewer agent turns on the same task.
  - **Measurement**: `bin/local-ai-bench --model gemma4:26b` vs `bin/local-ai-bench --model qwen3-coder:30b` on an idle machine (load1 under 5), plus one `bin/local-ai-agent` run each.
  - **Success**: tok/s ratio ≥ 1.2 and turns ≤ baseline: swap.
  - **Pivot**: tok/s ratio < 1.05 or more turns: keep qwen3-coder and re-check when Ollama ships MTP for other models.
  - **Anchor**: `docs/audits/local-ai-task-runs-2026-05-11.md` MAPE-K method; Ollama PR #15980 (MTP).
  - **Surfaced-by**: 2026-05-15 session — Gemma 4 release (April 2026)
    plus existing roadmap entries flagging MLX + spec-decoding advantages
    that haven't been benched yet on this stack.

- [ ] Investigate Ollama upstream qwen3-coder XML-parser fix (PRs #14906 / #14915)
  - **ID**: track-ollama-qwen3coder-parser-fix
  - **Tags**: local-ai, upstream, ollama
  - **Blocked**: needs-external-action — upstream fix has NOT shipped: PR ollama/ollama#14906 closed UNMERGED, successor #14915 still open, issue #14834 still open (checked 2026-06-12 and again 2026-10-16 via api.github.com; local Ollama is 0.40.5). Unblock when #14915 (or equivalent) merges into a tagged Ollama release; then simplify the retry ladder per Acceptance.
  - **Research**: 2026-06-12 — upstream status check
    `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14906` → state=closed, merged=false.
    `.../pulls/14915` → state=open. `.../issues/14834` → state=open.
    Watch-list entries + an anonymous-API fallback snippet added to docs/local-ai-roadmap.md
    (this host has no github.com gh auth; the API check needs no token).
    Re-check command: `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14915 | jq '{state, merged, merged_at}'`.
  - **Last-enriched**: 2026-10-16
  - **Details**: The 3-stage retry ladder in lib/local-ai-agent.py
    is a workaround for ollama/ollama#14834 — the qwen3-coder XML
    tool-call parser crashes with HTTP 500 on certain model
    outputs. Upstream PRs #14906 and #14915 propose to treat
    unparseable tool calls as content instead of aborting. Once
    one of those lands in a tagged Ollama release, simplify our
    retry ladder (we can drop the temperature wiggle once
    deterministic temp=0 retries no longer crash). Also update
    `docs/audits/local-ai-failure-modes.md` to mention which
    Ollama version fixes it.
  - **Files**: lib/local-ai-agent.py,
    docs/audits/local-ai-failure-modes.md
  - **Acceptance**: When the fix ships in Ollama, our retry
    ladder is simplified (1 retry, no temperature wiggle) and a
    new failure-mode entry records the Ollama version threshold.
  - **Hypothesis**: Removing the temperature retry ladder after Ollama fixes qwen3-coder parsing will simplify local-ai runs without increasing crashes.
  - **Success**: On a fixed Ollama release, local-ai-agent succeeds with one retry and no temperature wiggle on the known failure prompt.
  - **Pivot**: If upstream fix does not cover our crash shape, keep the ladder and update the failure-mode doc with version evidence.
  - **Measurement**: `lib/local-ai-agent.py` retry tests pass and a recorded Ollama version threshold is added to docs.
  - **Anchor**: ollama/ollama#14834 and PRs #14906/#14915; docs/user-stories/09-run-local-models-fast.md.

- [ ] Cross-repo local-AI loop (currently dotfiles-only)
  - **ID**: local-ai-loop-cross-repo
  - **Blocked**: needs the loop's default model `qwen3-coder:30b` (about 18 GB), which is not on disk (checked 2026-10-16), to prove a real run in a second repo. The config extraction itself can be tested with a stub agent, as `tests/local-ai-loop-branching.bats` does. Unblock: local AI back in use with the default model pulled.
  - **Tags**: local-ai, cross-repo, refactor
  - **Details**: `bin/local-ai-loop` hardcodes assumptions that
    only hold in `dotfiles/`: `make check` exists, `bats tests/`
    works, `git-hooks/` is the hook dir, the failure-modes file
    lives at `docs/audits/local-ai-failure-modes.md`. Extract the
    repo-specific bits into a `.local-ai-loop.json` config file
    per repo (verify_cmd, test_cmd, hook_dir, failure_modes_path,
    safe_prefixes). Move the standalone driver to
    `~/apps/tooling/agentbrew/skill-plugins/workflow/local-ai-loop/` so other
    repos can opt-in via `agentbrew sync`. Validate on
    `agentbrew` and `tasks.md`.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py,
    .local-ai-loop.json (new), ~/apps/tooling/agentbrew/skill-plugins/workflow/
  - **Acceptance**: `local-ai-loop` runs successfully from at
    least 2 different repos (dotfiles + one other), each with its
    own `.local-ai-loop.json`. Original dotfiles flow still works.
  - **Hypothesis**: Extracting repo-specific local-ai-loop config lets the runner work beyond dotfiles without hardcoded make/bats assumptions.
  - **Success**: The loop completes a task in dotfiles and one other repo using per-repo `.local-ai-loop.json` configs.
  - **Pivot**: If cross-repo differences are too large, keep dotfiles as the only supported repo and document required adapter hooks.
  - **Measurement**: `local-ai-loop` fixture tests cover two config files and both runs reach verification.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Stretch the loop to genuine feature work (patch_file in anger)
  - **ID**: local-ai-loop-feature-work-dogfood
  - **Blocked**: needs a real model run; the loop's default `qwen3-coder:30b` (about 18 GB) is not on disk (checked 2026-10-16). Unblock: local AI back in use with the default model pulled.
  - **Tags**: local-ai, dogfood, patch_file
  - **Details**: Earlier loop runs only produced new static test files. The harder case is editing an existing file with `patch_file`. Pick one open dotfiles task that edits a large existing file (for example `module-resilience-bats-missing-lib` or `launchagent-path-fix-stub-plist-message`), run the loop on it, and record where `patch_file` breaks.
  - **Files**: the chosen task's files, docs/audits/local-ai-failure-modes.md
  - **Acceptance**: At least one task that modifies an existing
    file > 100 lines via `patch_file` completes end-to-end. New
    failure modes captured in
    `docs/audits/local-ai-failure-modes.md`.
  - **Hypothesis**: Forcing local-ai-loop to patch an existing >100-line file will reveal real edit-path failures hidden by static test tasks.
  - **Success**: At least one existing-file modification task completes end-to-end with correct tests and failure-mode notes updated.
  - **Pivot**: If patch_file remains unreliable, add a smaller patching harness before using the loop on feature work.
  - **Measurement**: The chosen task edits a large existing file, passes `make check`, and its failures are recorded in docs/audits/local-ai-failure-modes.md.
  - **Anchor**: docs/audits/local-ai-failure-modes.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Run the local-AI loop for 8 hours from a task queue and log the success rate
  - **ID**: local-ai-loop-overnight-grind
  - **Blocked**: an 8-hour measured run, over the 60-minute agent limit, and the default model `qwen3-coder:30b` (about 18 GB) is not on disk (checked 2026-10-16). Per-task branches shipped (#115); the run is the only remaining step.
  - **Tags**: local-ai, automation, overnight
  - **Details**: The queue reader (`read_queue_dir`, `lib/local-ai-loop.py`), the run CSV, and the reviewer gate already shipped. What remains is the measured long run. Per-task branches (`overnight-grind-branch-per-task`) shipped on 2026-10-16. The loop never pushes, so each task ends as a local branch or a rollback note, not a PR. The loop last ran on 2026-05-11 and no inference engine is reachable today, so this waits until local AI is back in use.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py, docs/local-ai-roadmap.md
  - **Acceptance**: `./bin/local-ai-loop --queue tasks-queue/` runs for 8 hours and writes one CSV row per task with status, wall time, and regression outcome.
  - **Hypothesis**: Running queued local-AI tasks for hours exposes success-rate and rollback failure modes that one-task tests hide.
  - **Success**: An 8-hour run completes at least 80% of seeded tasks or records a rollback note for each failure.
  - **Pivot**: If the success rate is below 80%, pause feature work and fix the top recurring failure in the run CSV.
  - **Measurement**: `docs/audits/local-ai-runs.csv` rows for the run.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

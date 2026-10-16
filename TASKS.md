# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

- [ ] dotfiles meets every new-project requirement, or waives it with a reason
  - **ID**: meet-new-project-requirements
  - **Tags**: requirements, agents, observability, docs
  - **Details**: The 2026-10-16 audit scored dotfiles 11/24 with `.agents/requirements.yaml` (7/22 before the map). By intent: e2e, tasks, checkup, and caching are met; vision, metrics, observability, user stories, setup, and self-improving are partial. Fix in this order:
    1. Two tests fail on HEAD: cut `AGENTS.md` below 10000 bytes (`tests/docs-contract.bats` test 2); add the `load-sampler` row to `docs/user-stories/02-start-day-ready-to-code.md` (`tests/user-stories.bats` test 5).
    2. `VISION.md`: a success metric (scorecard north star, shell startup under 200 ms), kill criteria phrased per wrapper ("deprecate wrapper X if metric Y trails by date Z"), and `## Prior art` linking `docs/competition/scorecard.md`.
    3. `docs/competition/scorecard.md`: Goal and Pivot columns per metric; `(stub)` when data is missing.
    4. `README.md`: `bin/dotfiles-install run` (or a one-liner around it) is the single first quick-start command, ending with `dotfiles-doctor`; demote the other entry points.
    5. `docs/user-stories/*.md`: `Metric:` and `Tests:` lines per story; `tests/user-stories.bats` fails when a named test is missing.
    6. New `docs/observability.md` (in the docs map): events in `~/.dotfiles-stats.jsonl` and `load-samples.tsv`, and an errors log contract. `bin/dotfiles-doctor` and the LaunchAgent jobs append failures with a `story` field to `~/.local/state/dotfiles/errors.jsonl`.
    7. `make check` writes per-step durations to `~/.local/state/dotfiles/gate-timings.jsonl`, shown by `bin/dotfiles-metrics`; the speed review stays in `/tooling-checkup`.
    8. New `docs/learnings.md` (predicted vs observed), seeded from closed hypotheses; `docs/decisions/` ADRs from the ROADMAP decision log.
    9. `.gitignore`: `.env`, `.env.*`; extend the rule-9 lint to P2 or record why P2 is exempt.
    Requirement updates from the tasks.md 100% run (2026-10-16, new-project skill): each story's metric is an outcome rate, not a passing-test count; each e2e test names its story ID; the event writer allow-lists string fields and tests turn the log off; a metric whose source answers 0 for a missing thing shows `(stub)`; every `dotfiles-doctor` failing line carries its fix; the cache key lists every file a step reads (prove it by editing one file); the README setup block ends with the doctor. Worked example: tasks.md PRs #26-#34.
    Accepted push back (map or waive, do not build): no `scripts/*.sh` aliases for `bin/` commands; setup may prompt when macOS requires it; no external error reporter; timings live under `~/.local/state/dotfiles`, not `.metrics/`; no hermetic e2e for US-07 and US-09 (unit bats instead); the speed review lives in `/tooling-checkup`, not a second `RECURRING.md`.
  - **Files**: `AGENTS.md`, `VISION.md`, `README.md`, `docs/`, `bin/dotfiles-doctor`, `Makefile`, `.gitignore`, `.agents/requirements.yaml`
  - **Output**: code
  - **Acceptance**: `check-setup.sh . --profile tool` reaches 100% with every remaining gap mapped or waived with a reason, and `make check` passes.
  - **Hypothesis**: the setup score rises from 45% to 100%, honestly mapped or waived, and the monthly audit finds no new gap.
  - **Measurement**: `bash ~/.claude/skills/new-project/scripts/check-setup.sh . --profile tool`
  - **Success**: 100%, every waiver reasoned, `make check` green.
  - **Pivot**: a gap that costs more than it returns here becomes a waiver, or a requirement-change PR on agentbrew `new-project`.
  - **Anchor**: agentbrew `skill-plugins/workflow/new-project/references/requirements-map.md`; audit 2026-10-16.

## P1

- [ ] The commit-msg hook keeps git trailers last when it adds the agent footer
  - **ID**: commit-msg-footer-keeps-git-trailers-last
  - **Tags**: git-hooks, agents, bug
  - **Details**: `lib/strip-agent-attribution.sh` (run by `git-hooks/commit-msg`). When the hook strips a vendor attribution line, it appends `---` and the agent footer at the very end of the message. If the message ends with git trailers (`Task:`, `Task-Claim:`, `Signed-off-by:`), the footer becomes the last paragraph, so git no longer parses them (`git log --format='%(trailers:key=Task)'` is empty). On 2026-10-16 this failed the tasks.md required `claim-check` on PR #26 ("resolved task='' claim=''"). Fix: insert the footer before the trailing trailer block (use `git interpret-trailers --parse` to find it), and add a fixture test with a message ending in `Task:`/`Task-Claim:` trailers. agentbrew has a twin copy in `hooks/lib/` (task `strip-attribution-footer-keeps-git-trailers-last`).
  - **Competitive-goal**: none — commit-hook correctness; no scorecard metric covers git hooks.
  - **Measurement**: a `tests/` fixture that runs `git-hooks/commit-msg` on a message ending in `Task:`/`Task-Claim:` trailers and a stripped `Co-Authored-By:` line, then checks `git interpret-trailers --parse`.
  - **Hypothesis**: placing the footer before the trailer block keeps trailers parseable; commits whose trailers the hook breaks drop from every agent commit with trailers to 0.
  - **Success**: the new fixture passes, `git log -1 --format='%(trailers:key=Task-Claim,valueonly)'` prints the claim after the hook runs, and existing hook fixtures stay green.
  - **Pivot**: if trailer detection misfires on plain prose endings, require a `Key: value` block that git itself parses (`git interpret-trailers --parse` non-empty) before moving anything.
  - **Anchor**: git-interpret-trailers(1) (trailers must be the last paragraph); tasks.md docs/learnings.md row 2026-10-16.

## P2

- [ ] `dotfiles add` keeps a nested config file at its own path
  - **ID**: dotfiles-add-nested-path
  - **Tags**: us03, add, bug
  - **Details**: In symlink mode, `bin/dotfiles-add ~/.config/tool/tool.conf` copies the file to `home/tool.conf` and writes `symlink_dot_tool.conf.tmpl`, so `dotfiles apply` links `~/.tool.conf` instead of `~/.config/tool/tool.conf`. Found while writing the US03 story e2e (2026-10-16), which uses a top-level dotfile for now. Keep the path under `$HOME` (for example `dot_config/tool/symlink_tool.conf.tmpl`), and add a nested-file case to `tests/e2e/stories-e2e.bats`.
  - **Files**: `bin/dotfiles-add`, `tests/dotfiles-add-family.bats`, `tests/e2e/stories-e2e.bats`
  - **Output**: code
  - **Competitive-goal**: none — US03 correctness; no scorecard metric covers `dotfiles add`.
  - **Acceptance**: after `dotfiles add ~/.config/x/y.conf` and `dotfiles apply`, `~/.config/x/y.conf` is a symlink into the repo, and no `~/.y.conf` appears.
  - **Hypothesis**: nested files that `dotfiles add` deploys to the wrong path go from 1 of 1 to 0 of 1.
  - **Measurement**: `make e2e` (new US03 nested-file case).
  - **Success**: the nested case passes.
  - **Pivot**: if chezmoi's own `chezmoi add --follow` covers this, drop symlink mode for nested files and call it (GET over IMPLEMENT).
  - **Anchor**: US03 story e2e finding 2026-10-16.

- [ ] Endpoint hardening runs only on Macs that need it
  - **ID**: endpoint-hardening-only-where-needed
  - **Tags**: endpoint, homebrew, new-users, portability
  - **Details**: `run_after_endpoint-security.sh`, `run_at_login_endpoint-bootstrap.sh`, and `run_at_login_sign-uv-python.sh` ad-hoc sign Homebrew bottles and link shims into `/opt/homebrew/bin` on every apply, on every Mac. They exist for a managed endpoint-security agent. The hermetic install e2e (2026-10-16) showed they write outside `$HOME` on a new user's Mac too. Gate them on `dotfiles_managed_endpoint` or `owner_machine`, keep today's behaviour on the owner's Macs, and drop `DOTFILES_SKIP_ENDPOINT_HARDENING` from the e2e once the gate covers it.
  - **Files**: `.chezmoiscripts/run_after_endpoint-security.sh`, `.chezmoiscripts/run_at_login_*.sh`, `tests/e2e/hermetic-install.sh`
  - **Output**: code
  - **Acceptance**: the e2e passes without `DOTFILES_SKIP_ENDPOINT_HARDENING`; the owner's apply still signs bottles.
  - **Hypothesis**: Homebrew-prefix writes during a new user's install go from about 10 to 0.
  - **Measurement**: `make e2e` with the skip variable removed (the sandbox fails any write outside the scratch HOME).
  - **Success**: e2e green with no skip variable.
  - **Pivot**: if a new user does need signing (an endpoint agent detected late), detect it at apply time instead of gating up front.
  - **Anchor**: Basili et al. 1994 (GQM); hermetic install e2e findings 2026-10-16.

- [ ] A new user's agents get only general rules from the dotfiles Agentfile
  - **ID**: agentfile-rules-owner-only-split
  - **Tags**: agentbrew, rules, new-users, portability
  - **Details**: `Agentfile.yaml` `rules:` deploys to every Mac that runs dotfiles. Some lines are the owner's personal workflow, not general advice: the "**Needed from you:**" closing line, the memory-MCP calls (`get_bootstrap_profile`, `commit_session_legacy`), the Augment/Windsurf/Devin notes, and the approved-family delivery pointer. A new user gets them too. Split them into an owner-only rules block that `dotfiles apply` merges only when `owner_machine` is true (like the hooks overlay), and keep only general rules in `Agentfile.yaml`.
  - **Files**: `Agentfile.yaml`, `bin/dotfiles-apply` or the Agentfile merge step, `tests/stranger-readiness.bats`
  - **Output**: code
  - **Acceptance**: a stranger render (owner_machine false) produces an agentbrew Agentfile without the owner-only lines; the owner's still has them.
  - **Hypothesis**: owner-only rule lines a new user's agents load go from about 8 to 0, with no change on the owner's Macs.
  - **Measurement**: `bats tests/stranger-readiness.bats` (new case greps the merged Agentfile for the owner-only lines).
  - **Success**: 0 owner-only lines for a stranger, all present for the owner.
  - **Pivot**: if the merge step cannot see `owner_machine`, move the owner lines to the owner's local `~/.config/agentbrew/shared-rules.md` instead.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); finding from the 2026-10-16 portability audit.

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

# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

## P1

## P2

- [ ] User-dir installers for AWS CLI v2 and the gcloud SDK, so `dotfiles apply` reproduces them without brew Python
  - **ID**: user-dir-installers-for-aws-gcloud
  - **Tags**: scout, brew, arm64-migration, endpoint-security, reproducibility
  - **Details**: The arm64 Homebrew migration removed `awscli` and the `gcloud-cli` cask from the inline Brewfile. Both pull `python@3.x`, and endpoint agents flag that Python on every spawn (see the NOTE in `.chezmoiscripts/run_onchange_brew.sh.tmpl` and AGENTS.md rule #10). The tools were then installed into user dirs by hand: AWS CLI v2 from `AWSCLIV2.pkg`, unpacked to `~/.local/aws-cli` and symlinked into `~/.local/bin`; the Google Cloud SDK from `https://sdk.cloud.google.com` into `~/google-cloud-sdk`, symlinked into `~/.local/bin`. `run_after_uv-tools.sh` reproduces poetry, httpie, and jrnl, but AWS CLI v2 is not on PyPI and gcloud is not a uv tool. So a fresh `dotfiles apply` installs neither, although both scripts already point at this task ID. Add `.chezmoiscripts/run_once_install_aws_gcloud.sh` (or extend `run_after_uv-tools.sh`) that: (1) when `~/.local/bin/aws` is absent, downloads `https://awscli.amazonaws.com/AWSCLIV2.pkg`, runs `pkgutil --expand-full`, copies the `aws-cli` payload to `~/.local/aws-cli`, and symlinks `aws` and `aws_completer` into `~/.local/bin`; (2) when `~/google-cloud-sdk` is absent, runs the gcloud install script with `--disable-prompts --install-dir="$HOME"` and symlinks `gcloud`, `gsutil`, and `bq` into `~/.local/bin`. Gate both behind `.is_enterprise` (where `awscli` used to live) and skip cleanly when the tool is already present. The `enterprise.aws` doctor fix hint still says `brew install awscli`; point it at the new installer and add checks that `aws` and `gcloud` resolve under `~/.local`.
  - **Files**: `.chezmoiscripts/run_once_install_aws_gcloud.sh` (new), `modules/enterprise/doctor.sh`, `tests/chezmoiscripts.bats`, `docs/what-gets-changed.md`
  - **Acceptance**: On a fresh machine with `is_enterprise: true`, `dotfiles apply` leaves `command -v aws` at `~/.local/bin/aws` (v2) and `command -v gcloud` at `~/.local/bin/gcloud`, and neither spawns brew Python. A second `dotfiles apply` is a no-op for both. The enterprise doctor checks pass.
  - **Hypothesis**: A user-dir installer makes AWS CLI v2 and gcloud reproducible, so manual install steps after a fresh enterprise apply drop from 2 to 0.
  - **Success**: On a clean enterprise-profile HOME, one `dotfiles apply` installs both tools under `~/.local/bin`, and a second apply changes nothing.
  - **Pivot**: If either vendor installer needs admin rights or triggers an endpoint prompt, stop and document one `needs-user-action` step instead.
  - **Measurement**: `command -v aws gcloud | grep -c "$HOME/.local/bin/"` reads 2 after a fresh `dotfiles apply` with `is_enterprise: true`.
  - **Anchor**: AGENTS.md rule #10 (user-dir installs over admin paths); chezmoi `run_once_` script docs; AWS CLI v2 "install for the current user" macOS docs.

## P3

- [ ] Replace? Relocate: update-tooling orchestration
  - **ID**: replace-relocate-update-tooling-orchestration
  - **Tags**: scout, tooling, agentbrew, dotfiles, reuse, upstream
  - **Details**: The `update-tooling` skill currently coordinates safe primary-checkout refresh, the chezmoi applied checkout, agentbrew sync and health checks, and task ranking. Re-evaluate whether a maintained upstream tool can own more of this workflow without losing the local ownership boundary: dotfiles owns the host and Agentfile; agentbrew owns generated agent configuration. Prefer a pointer or thin adapter when an upstream workflow can preserve fast-forward-only Git behavior, applied-checkout safety, and non-destructive task recommendations.
  - **Files**: skills/update-tooling/SKILL.md, Agentfile.yaml, README.md
  - **Acceptance**: Record one current decision in the skill or README: replace with an upstream tool, relocate a portion to agentbrew or chezmoi, or keep the skill with a specific local-only reason. If a maintained upstream covers the workflow, remove duplicated guidance and point to that source.

- [ ] Evaluate Gemma 4 26B (and E4B) as a replacement for qwen3-coder:30b in the local-AI stack
  - **ID**: bench-gemma4-vs-qwen3-coder-local-ai
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
  - **Blocked**: needs-external-action — upstream fix has NOT shipped: PR ollama/ollama#14906 closed UNMERGED, successor #14915 still open, issue #14834 still open (checked 2026-06-12 via api.github.com). Unblock when #14915 (or equivalent) merges into a tagged Ollama release; then simplify the retry ladder per Acceptance.
  - **Research**: 2026-06-12 — upstream status check
    `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14906` → state=closed, merged=false.
    `.../pulls/14915` → state=open. `.../issues/14834` → state=open.
    Watch-list entries + an anonymous-API fallback snippet added to docs/local-ai-roadmap.md
    (this host has no github.com gh auth; the API check needs no token).
    Re-check command: `curl -sf https://api.github.com/repos/ollama/ollama/pulls/14915 | jq '{state, merged, merged_at}'`.
  - **Last-enriched**: 2026-06-12
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
  - **Tags**: local-ai, automation, overnight
  - **Details**: The queue reader (`read_queue_dir`, `lib/local-ai-loop.py`), the run CSV, and the reviewer gate already shipped. What remains is the measured long run. It needs `overnight-grind-branch-per-task` first. The loop never pushes, so each task ends as a local branch or a rollback note, not a PR. The loop last ran on 2026-05-11 and no inference engine is reachable today, so this waits until local AI is back in use.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py, docs/local-ai-roadmap.md
  - **Acceptance**: `./bin/local-ai-loop --queue tasks-queue/` runs for 8 hours and writes one CSV row per task with status, wall time, and regression outcome.
  - **Hypothesis**: Running queued local-AI tasks for hours exposes success-rate and rollback failure modes that one-task tests hide.
  - **Success**: An 8-hour run completes at least 80% of seeded tasks or records a rollback note for each failure.
  - **Pivot**: If the success rate is below 80%, pause feature work and fix the top recurring failure in the run CSV.
  - **Measurement**: `docs/audits/local-ai-runs.csv` rows for the run.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Overnight grind sub-task 3 — per-task dogfood branch, merge-or-revert
  - **ID**: overnight-grind-branch-per-task
  - **Parent**: local-ai-loop-overnight-grind
  - **Tags**: local-ai, automation, overnight, git-safety
  - **Details**: Each queue task runs on its own `dogfood/<task-id>` branch from the starting HEAD; on a fully-gated success (make check + reviewer gate from the shipped pre-merge reviewer) merge back to the starting branch, on failure abandon the branch after `revert_uncommitted` and record a rollback note (CSV outcome + log line). Optional `--open-prs` flag covers the epic's "opens N PRs" acceptance; pushing stays opt-in per the bin header's "loop never pushes" contract.
  - **Files**: lib/local-ai-loop.py, tests/local-ai-loop-branching.bats (new), bin/local-ai-loop, docs/local-ai-roadmap.md
  - **Acceptance**: fixture run shows success-task merged to the starting branch and failure-task branch abandoned with a rollback note; multi-agent git-safety rules respected (no reset --hard/checkout ./clean -fd); `make check` exits 0.
  - **Hypothesis**: Branch isolation per task prevents failure-mode pollution between queued tasks over an 8h run.
  - **Success**: Per-task branches merge or are abandoned strictly by the existing close gates.
  - **Pivot**: If branch churn confuses the auto-sync agent, run the whole queue on one grind branch and rely on revert_uncommitted isolation.
  - **Measurement**: `bats tests/local-ai-loop-branching.bats` exits 0.
  - **Anchor**: parent task local-ai-loop-overnight-grind Acceptance; CLAUDE.md multi-agent git-safety rules.

- [ ] Doctor flags deployed LaunchAgents from other owners that run without a locale
  - **ID**: doctor-launchagent-locale-other-owners
  - **Tags**: scout, launchagents, doctor, locale
  - **Details**: `tests/launchagents.bats` now requires `LANG=C.UTF-8` in every dotfiles plist, because launchd sets no locale and the `bin/awk` shim (Homebrew gawk) then fails unanchored regex matches. Plists from other owners are not covered: a third-party plist in `~/Library/LaunchAgents/` sets only `PATH` and `HOME`. Add one advisory doctor check that lists deployed non-`com.dotfiles.*` plists without `LANG` or `LC_ALL`, and file the fix in each owning repo.
  - **Files**: modules/security/doctor.sh (next to the existing `security.deployed_la_*` checks)
  - **Acceptance**: `dotfiles doctor` warns once, naming each deployed plist without a locale; no dotfiles code writes plists it does not own.

- [ ] Replace? Relocate: agent-browser singleton helpers
  - **ID**: replace-relocate-agent-browser-singleton-helpers
  - **Tags**: scout, agent-browser, reuse, upstream
  - **Details**: `bin/agent-browser-singleton-preflight`, `bin/agent-browser-reap-strays`, and the safe `~/.agent-browser/{ensure,launch}-chrome.sh` compatibility wrappers are intentionally thin host-local adapters over `agent-browser --cdp` and Chrome CDP. Revisit whether this layer should be contributed upstream to agent-browser, moved into agentbrew shared browser policy tooling, or kept in dotfiles because it depends on this repo's launchd profile/port contract.
  - **Files**: bin/agent-browser-singleton-preflight, bin/agent-browser-reap-strays, private_dot_agent-browser/executable_ensure-chrome.sh, private_dot_agent-browser/executable_launch-chrome.sh, modules/agent-browser/doctor.sh
  - **Acceptance**: Document one decision: upstream PR/filed issue, relocation to agentbrew, or "keep in dotfiles" with a current reason; if relocating, add/point to the implementation task in the owning repo.

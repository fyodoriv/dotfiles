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

- [ ] Spotlight doctor checks prove indexing is off, not only that the marker file exists
  - **ID**: spotlight-marker-checks-verify-exclusion
  - **Tags**: spotlight, doctor, workflow, macos, correctness
  - **Details**: Verified on `feat/chezmoi` at 2377a45. `modules/workflow/doctor.sh:52-54` reports "`$dir` excluded from Spotlight" when `[ -f "$dir/.metadata_never_index" ]` passes. `macos.sh:66-71` and `modules/agent-browser/doctor.sh:69-71` use the same marker. On this macOS the marker did not stop indexing: worktrees under `~/apps/tooling/wt` were indexed until #83 renamed the folder to `wt.noindex`. The repo already says so in `modules/workflow/doctor.sh:57-58`, `lib/agent-worktrees-noindex.sh:6-8`, and `docs/module-reference.md:107`. But `docs/module-reference.md:106` and `docs/security-model.md:142` still promise the marker excludes 11 dev dirs. `~/apps/.metadata_never_index` exists today, so the check passes whatever Spotlight does. Fix: test real exclusion (for example `mdfind -onlyin <dir>` for a known file, or the `.noindex` rename/symlink from #83 where safe), or reword the check as "marker present" and fix the docs.
  - **Files**: modules/workflow/doctor.sh, macos.sh, modules/agent-browser/doctor.sh, docs/module-reference.md, docs/security-model.md, tests/module-workflow.bats
  - **Acceptance**: No doctor check prints "excluded from Spotlight" unless a probe shows the dir is out of the index. The docs match what the checks prove.
  - **Hypothesis**: Probing the index instead of the marker file drops false "excluded" passes from 11 of 11 marker dirs to 0.
  - **Success**: A bats fixture where the marker exists but the probe finds an indexed file makes the check fail; real excluded dirs still pass.
  - **Pivot**: If `mdfind` is too slow or flaky for doctor (over 1 s per dir), rename the check to "marker present" and move the real probe to `/tooling-checkup`.
  - **Measurement**: `bats tests/module-workflow.bats` plus `dotfiles doctor --module workflow` on this Mac.
  - **Anchor**: #83 (wt.noindex rename); Apple `mdutil(1)`/`mdfind(1)`.
  - **Competitive-goal**: reproducibility_pct — a fresh apply must give the same, real Spotlight exclusion each time, not a marker that some macOS versions ignore.

- [ ] `dotfiles-doctor --quiet` names each failing check
  - **ID**: doctor-quiet-names-failing-checks
  - **Tags**: doctor, cli, ux
  - **Details**: Verified on `feat/chezmoi` at 2377a45. In quiet mode `bin/dotfiles-doctor:914-917` prints only counts: `✓ $pass_count  ✗ $fail_count  ⊘ $skip_count`. Today's `dotfiles apply` showed `✓ 511 ✗ 1 ⊘ 6` with no check name. The user must re-run without `--quiet` (a 500+ check pass) to learn which check failed. Append the failing check IDs (up to about 5, then "+N more") to the quiet line.
  - **Files**: bin/dotfiles-doctor, tests/dotfiles-doctor.bats, docs/module-reference.md
  - **Acceptance**: `dotfiles-doctor --fix --quiet` with one failing check prints that check's ID on the summary line; the all-pass line is unchanged.
  - **Hypothesis**: Naming failed IDs in the quiet line cuts the extra full doctor runs needed to find a failure from 1 to 0.
  - **Success**: A bats fixture with one failing check finds its ID in quiet output.
  - **Pivot**: If callers parse the quiet line, put the IDs on a second line instead and keep line 1 byte-identical.
  - **Measurement**: `bats -f quiet tests/dotfiles-doctor.bats`.
  - **Anchor**: Nielsen 1994, heuristic 9 (help users recognize and diagnose errors).
  - **Competitive-goal**: manual_bootstrap_steps — `dotfiles doctor --fix` is step 4 of bootstrap; an unnamed ✗ adds a manual re-run.

- [ ] `tests/module-upgrade.bats` sets `auto_upgrade` itself so tests 2, 3, 4, 6, 8 pass
  - **ID**: module-upgrade-bats-auto-upgrade-fixture
  - **Tags**: tests, upgrade, bats
  - **Details**: Verified on `feat/chezmoi` at 2377a45: `bats tests/module-upgrade.bats` → `not ok` 2, 3, 4, 6, 8 (lines 66, 72, 78, 95, 113). Cause: `modules/upgrade/doctor.sh:13` reads `chezmoi execute-template '{{ dig "auto_upgrade" "false" . }}'` and registers `upgrade.launchagent`/`upgrade.recent` only when it is `true`. The test `setup()` sets `HOME` to a temp dir with no chezmoi config, so the value is `false` (`HOME=$(mktemp -d) chezmoi execute-template ...` → `false`) and the checks the tests count never run. So the failure does not need this Mac's data; it should fail on any machine. Not on the AGENTS.md "Known base failures" list. Fix: stub `chezmoi` on `PATH` in `setup()` (or seed `$HOME/.config/chezmoi/chezmoi.toml` with `auto_upgrade = true`), and add one test for the `false` path.
  - **Files**: tests/module-upgrade.bats
  - **Acceptance**: `bats tests/module-upgrade.bats` passes 11 of 11, plus a new test that both checks are skipped when `auto_upgrade` is false.
  - **Hypothesis**: Seeding `auto_upgrade` in the test fixture takes the file from 5 failures to 0 with no doctor code change.
  - **Success**: 0 failures in `tests/module-upgrade.bats` on two runs.
  - **Pivot**: If the gate in `modules/upgrade/doctor.sh` is wrong, fix the gate instead of the fixture.
  - **Measurement**: `bats tests/module-upgrade.bats`.
  - **Anchor**: Meszaros 2007, *xUnit Test Patterns* (fresh fixture; no hidden environment dependency).
  - **Competitive-goal**: reproducibility_pct — the suite that guards a reproducible apply must itself give the same result on every machine.

- [ ] `tests/cli.bats` "dotfiles cd" passes in a worktree whose path lacks "dotfiles"
  - **ID**: cli-bats-cd-test-path-independent
  - **Tags**: tests, cli, bats, worktrees
  - **Details**: Verified on `feat/chezmoi` at 2377a45. `tests/cli.bats:85-90` asserts `[[ "$output" == *"dotfiles"* ]]`. `bin/dotfiles:245-246` prints `$DOTFILES_DIR`, which is the checkout path (`bin/dotfiles:10`). In a detached worktree at `~/apps/tooling/wt/df-cdprobe` the test failed: `not ok 1 dotfiles cd prints dotfiles directory` (line 88). Fix: assert that the output equals the repo root of the test checkout (`$DOTFILES_DIR`) and that `bin/dotfiles` exists under it.
  - **Files**: tests/cli.bats
  - **Acceptance**: The test passes in a worktree whose path has no "dotfiles", and still fails if `dotfiles cd` prints a wrong dir.
  - **Hypothesis**: Asserting on the real repo root instead of a path substring takes failures in non-"dotfiles" worktrees from 1 to 0.
  - **Success**: `bats -f 'dotfiles cd prints' tests/cli.bats` passes in such a worktree.
  - **Pivot**: None needed; if `DOTFILES_DIR` is not reliable in the test, compare with `git rev-parse --show-toplevel`.
  - **Measurement**: `bats -f 'dotfiles cd prints' tests/cli.bats` run from `~/apps/tooling/wt/<name-without-dotfiles>`.
  - **Anchor**: Meszaros 2007, *xUnit Test Patterns* (no test dependency on the run location).
  - **Competitive-goal**: reproducibility_pct — gate results must not depend on the checkout path.

## P3

- [ ] Agent time review suggests a speedup task only for steps that recur across sessions
  - **ID**: agent-time-review-multi-session-recurrence
  - **Tags**: tooling-checkup, perf, false-positive
  - **Details**: `task_candidates` in `skills/tooling-checkup/scripts/agent_time_review.py` keeps a step when `count >= RECURRING_MIN_CALLS` (2) and it costs 1+ min/day. It does not check sessions, so a step that repeats inside one session counts as recurring. Example: a `cp` that was slow only once, under load ~53, produced a task suggestion. Checked on feat/chezmoi: the filter reads only `count` and `sumMs`, and the agentbrew `agent-perf.mjs report --json` key rows carry no session count. Fix: require the step in 2+ distinct sessions before suggesting a task, or normalise by load. This needs a per-key session count (add `sessions` to agentbrew `summarize`, or count distinct `sid` from the rows here).
  - **Files**: `skills/tooling-checkup/scripts/agent_time_review.py`, `tests/tooling-checkup-skill.bats`, `skills/tooling-checkup/SKILL.md`
  - **Output**: code
  - **Acceptance**: a fixture with one step repeated 3 times in one session gets no task suggestion; the same step in 2 sessions still gets one; the existing `agent_time_review.py` bats cases pass.
  - **Hypothesis**: requiring 2+ sessions removes single-session false-positive task suggestions without dropping real recurring steps.
  - **Measurement**: `python3 skills/tooling-checkup/scripts/agent_time_review.py --days 7 --json | jq '[.tasks[] | select(.sessions < 2)] | length'` (field name per the implementation; today no session field exists).
  - **Success**: 0 suggestions come from a single session, and every suggestion from the previous run that spans 2+ sessions is still listed.
  - **Pivot**: if per-key session counts cannot reach the script without an agentbrew change, normalise by load average instead and record why.
  - **Anchor**: agentbrew #114 (perf log design); Basili et al. 1994 (GQM).

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

- [ ] Shellcheck scans every `lib/*.sh` file, not a hand-kept list
  - **ID**: lint-scan-all-lib-scripts
  - **Tags**: lint, shellcheck, makefile
  - **Details**: Verified on `feat/chezmoi` at 2377a45. `Makefile` `SCRIPTS` lists some `lib/*.sh` files by name; about two thirds of `lib/*.sh` are not linted by `make lint`. Running `shellcheck -S warning` on the unlisted files finds 4 warnings in three files: `lib/apply-defaults.sh:52,55` SC2034, `lib/heal-stuck-agents.sh:273` SC2155, `lib/workspace-discovery.sh:36` SC2088. The SC2088 hit is a false positive (the `case` pattern matches a literal `~/` on purpose); it needs a `# shellcheck disable=SC2088` with a reason. Fix: use `$(wildcard lib/*.sh)` in `SCRIPTS` and clear or annotate the 4 warnings.
  - **Files**: Makefile, lib/apply-defaults.sh, lib/heal-stuck-agents.sh, lib/workspace-discovery.sh
  - **Acceptance**: `make lint` lints all `lib/*.sh` files and exits 0.
  - **Competitive-goal**: reproducibility_pct — indirect: lint catches shell bugs in the libraries every apply sources.

- [ ] `upgrade.poetry_runs` gets a safe, reversible `--fix`
  - **ID**: doctor-poetry-runs-fix
  - **Tags**: doctor, upgrade, poetry, uv
  - **Details**: Verified on `feat/chezmoi` at 2377a45. `modules/upgrade/doctor.sh:55-57` registers `check "upgrade.poetry_runs" ... "'$_poetry_bin' --version" ""`: the fix argument is empty, so `dotfiles doctor --fix` only prints the manual commands from the description. Add a fix that moves the old binary and `~/Library/Application Support/pypoetry/venv` aside to `*.bak` (no delete), then runs `uv tool install poetry`. Skip the fix when `uv` is missing.
  - **Files**: modules/upgrade/doctor.sh, tests/module-upgrade.bats, docs/module-reference.md
  - **Acceptance**: With a fake broken non-uv poetry in a fixture, `--fix` leaves `*.bak` copies and a working uv-managed `poetry`; a second run is a no-op.
  - **Competitive-goal**: manual_bootstrap_steps — the poetry repair moves from hand-typed commands into bootstrap step 4.

- [ ] Document or silence npm "failed to copy trust settings" in sandboxed agent runs
  - **ID**: npm-trust-settings-sandbox-noise
  - **Tags**: npm, node, agent-sandbox, docs
  - **Details**: Checked on this Mac on 2026-10-15. The message comes only from sandboxed agent shells with `NODE_USE_SYSTEM_CA=1`. Sandboxed `npm view semver version` printed `ERROR: failed to copy trust settings of system certificate-25291` 36 times. The same command with `env -u NODE_USE_SYSTEM_CA` printed it 0 times, and an unsandboxed run printed it 0 times. `NODE_USE_SYSTEM_CA` is not set anywhere in this repo (`rg NODE_USE_SYSTEM_CA` finds nothing), so it comes from the agent host. Decide: add an AGENTS.md Gotcha ("harmless; run npm unsandboxed or unset NODE_USE_SYSTEM_CA"), or file it with the owner of the host env.
  - **Files**: AGENTS.md
  - **Acceptance**: One recorded decision: a Gotcha line in AGENTS.md, or a filed upstream issue linked here.
  - **Competitive-goal**: manual_bootstrap_steps — indirect: less noise in agent npm runs; no shared metric moves.

- [ ] `tests/verify-counts.bats` "count prints live stats" stops counting the whole suite
  - **ID**: verify-counts-count-test-speed
  - **Tags**: tests, performance, bats, makefile
  - **Details**: Verified on `feat/chezmoi` at 2377a45. `tests/verify-counts.bats:77-82` runs `make count`. `Makefile:110` runs `bats --count tests/*.bats` over every bats file. At load1 3.4 that took 17.6 s (`/usr/bin/time -p bats --count tests/*.bats`). An agent reported about 9 minutes at high load on 2026-10-15 (the sampler shows load1 peaks of 84 today). `bin/bats-affected:234-262` adds this file for many doc and Makefile changes, so the cost lands on many affected-test runs. Fix: let the test set a small `TESTS_GLOB` (for example one fixture file) for `make count`, or count `@test` lines with `rg -c` instead of `bats --count`.
  - **Files**: Makefile, tests/verify-counts.bats
  - **Acceptance**: The test runs in under 2 s at low load and still checks the `Modules:` and `macOS defaults:` lines.
  - **Competitive-goal**: noop_reapply_ms — indirect: faster local gates; no shared metric moves.

- [ ] Measure `mdworker` CPU for 10 minutes after a 10-worktree session (#83 open acceptance)
  - **ID**: spotlight-wt-noindex-mdworker-measurement
  - **Tags**: spotlight, measurement, worktrees
  - **Output**: measurement
  - **Details**: #83 (714cab5) moved agent worktrees to `~/apps/tooling/wt.noindex`. Its PR body says the pre-registered 10-minute `mdworker` CPU window was not run: two forced Mac resets killed the sampler. Only a 0% spot check with 12 worktrees exists. No open task covers it (`rg -i 'mdworker|spotlight' TASKS.md` finds nothing). Run it once during a `/tooling-checkup`, with no polling loop: sample at 0, 5, and 10 minutes.
  - **Files**: none (record the result in the next tooling-checkup report or the #83 PR)
  - **Acceptance**: Three samples recorded with time, load1, and worktree count. Success: `mdworker` total stays under 50% CPU in all three. If not, reopen the Spotlight work with the numbers.
  - **Competitive-goal**: reproducibility_pct — indirect: confirms the #83 apply result holds on a busy Mac.

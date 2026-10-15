# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

## P1

- [ ] Keep Spotlight out of the agent worktree folder
  - **ID**: spotlight-exclude-agent-worktrees
  - **Tags**: scout, performance, macos, worktrees
  - **Details**: Agents create many git worktrees under `~/apps/tooling/wt`, each with its own `node_modules`. Spotlight (`mdworker`) indexes all of them. On 2026-10-12, about 25 worktrees from one session kept load near 44 on 10 cores after the work had stopped. Make `dotfiles apply` exclude the folder from Spotlight without admin rights, for example with a `.metadata_never_index` marker file, and have the doctor check it.
  - **Files**: bin/dotfiles, bin/dotfiles-doctor, tests/
  - **Acceptance**: `~/apps/.metadata_never_index` has existed since 2026-09-27, yet mdworker still indexed the worktrees on 2026-10-12, so the marker alone does not work. Either move agent worktrees to a `.noindex` folder (for example `~/apps/tooling/wt.noindex`, updating every script and doc that names `wt`), or add a doctor hint with the Spotlight Privacy-list or `mdutil` step for the user; then re-measure.
  - **Hypothesis**: Spotlight indexing of worktrees is the main load source after a parallel agent session; excluding the folder removes it.
  - **Success**: after a session that creates at least 10 worktrees, `mdworker` CPU stays under 50% total in the next 10 minutes.
  - **Pivot**: If neither a `.noindex` folder nor the Privacy list stops indexing, drop the exclusion and cap parallel worktrees instead.
  - **Measurement**: `ps -A -o %cpu,comm | rg mdworker | awk '{s+=$1} END {print s}'`
  - **Anchor**: Gregg, "Systems Performance", 2nd ed., 2020 (USE method).

- [ ] Explain the 10-minute `dotfiles-doctor --fix --quiet` run inside `dotfiles apply`
  - **ID**: doctor-fix-apply-wall-time-unexplained
  - **Tags**: scout, doctor, performance
  - **Details**: On 2026-10-12 a full `dotfiles-doctor --quiet` took 45-52s (load 30-40, warm cache) and 69s with a cold bottle cache. Yet `dotfiles-doctor --fix --quiet` inside `dotfiles apply` took about 10 minutes the same day. Read-only runs cannot explain it. Suspects: the cold bottle audit right after brew changes, each failing check's fix running up to `FIX_TIMEOUT` (30s), and load from the apply itself. `DOTFILES_DOCTOR_TIMING=1` now prints per-module seconds; make `bin/dotfiles` apply set it and keep the output in the doctor log so the next slow run names its module. New lead (2026-10-15): an apply started from a Claude desktop Code-tab session inherited the background band (nice 10, PRI 4) from `cursor-priority`; its `dotfiles-doctor --fix --quiet` step ran 29 minutes, then finished 7 s after `taskpolicy -B` lifted the band, and a standalone unthrottled `dotfiles doctor` took 50 s. The Claude.app ancestor fix removes that cause for Desktop sessions; re-measure before adding timing work.
  - **Files**: bin/dotfiles, bin/dotfiles-doctor
  - **Acceptance**: Step 1: re-measure `dotfiles apply` now that the PRI-4 band fix (#66) landed. If the doctor step takes at most 2 minutes, close this task as fixed by #66. Otherwise, after one `dotfiles apply` the doctor log holds a `doctor-timing:` block (set `DOTFILES_DOCTOR_TIMING` from `bin/dotfiles`).
  - **Hypothesis**: The slow part is one module or one fix, not the checks as a whole. The log shows it in one run.
  - **Success**: the log names the slowest module for every apply.
  - **Pivot**: if the timing block shows no module above 30s, profile the fix path instead.
  - **Measurement**: `rg -c 'doctor-timing:' ~/.local/share/dotfiles/logs/dotfiles-doctor.log`
  - **Anchor**: Basili, Caldiera, Rombach, "The Goal Question Metric Approach", 1994.

## P2

- [ ] Report Label-less LaunchAgent plists as stubs, not "not XML"
  - **ID**: launchagent-path-fix-stub-plist-message
  - **Tags**: scout, launchagents, ux
  - **Details**: `bin/dotfiles-fix-launchagent-endpoint-path` prints `⚠ Skipping invalid LaunchAgent plist (not XML)` for four Google Keystone and Dropbox updater plists on every upgrade. They are valid XML (`plutil -lint` OK) with an empty `<dict/>`: the vendors leave stubs behind. `_plist_valid` only checks for a `Label`. Say what is true (`no Label (empty stub)`) and skip stubs quietly, warning only when `plutil -lint` fails.
  - **Files**: bin/dotfiles-fix-launchagent-endpoint-path, tests/
  - **Acceptance**: a bats test with an empty-dict plist sees no warning, and a test with a malformed plist still warns.

- [ ] Flag a non-uv Poetry whose Python interpreter is gone
  - **ID**: doctor-broken-official-poetry
  - **Tags**: scout, doctor, python, upgrade
  - **Details**: On 2026-10-15 the official-installer Poetry (`~/.local/bin/poetry` plus `~/Library/Application Support/pypoetry/venv`) linked to pyenv Python 3.10.0, which no longer existed, so `poetry` and topgrade's Poetry step failed on every upgrade. `run_after_uv-tools.sh` saw the file and skipped `uv tool install poetry` ("already provided by ... not uv-managed"). The fix on that Mac was to move both paths aside and run `uv tool install poetry`. Have the doctor report a non-uv `poetry` whose `poetry --version` fails, with that fix as the hint.
  - **Files**: modules/*/doctor.sh, tests/
  - **Acceptance**: with a stub `poetry` that fails `--version` and is not under the uv tool dir, the doctor reports it with the move-aside and `uv tool install poetry` hint.

- [ ] Make `tests/module-resilience.bats` source the doctor module again
  - **ID**: module-resilience-bats-missing-lib
  - **Tags**: scout, tests, resilience
  - **Details**: The tmux tests fail on `feat/chezmoi` (d600271): `source modules/resilience/doctor.sh` stops because the test setup copies only `doctor.sh`, and the module now sources `lib/agent-keepawake.sh`. `make check` misses it because the file is not in the affected set unless the module changes.
  - **Files**: tests/module-resilience.bats
  - **Acceptance**: `bats tests/module-resilience.bats` passes; the setup copies or points at `lib/agent-keepawake.sh`; the test is removed from the AGENTS.md "Known base failures" list.

- [ ] Render npm `allow-scripts` into ~/.npmrc from the shared CLI list
  - **ID**: npmrc-allow-scripts-from-list
  - **Tags**: npm, upgrade, resilience
  - **Details**: `bin/dotfiles-npm-global-scripts` repairs a CLI after topgrade's `npm update --location=global` blocks its install scripts. A persistent `allow-scripts=` line in `~/.npmrc` would let the topgrade step succeed on its own. Render that line in `modify_private_dot_npmrc` from `data/npm-global-allow-scripts.json`, so the list stays in one place. Evidence 2026-10-15: every `dotfiles-upgrade` run prints `→ railway --version fails` after the npm step, and the custom step then reinstalls it; a manual `npm install -g @railway/cli` left it broken the same way.
  - **Files**: modify_private_dot_npmrc, data/npm-global-allow-scripts.json, tests/
  - **Acceptance**: a test renders the npmrc from a fixture list and finds one `allow-scripts=` line with every package; `npm update -g` on a fixture prefix keeps a script CLI working.
- [ ] dotfiles-audit tests pass on a machine with real shims
  - **ID**: dotfiles-audit-tests-pass-on-a-machine-with-real-shims
  - **Tags**: tests,audit
  - **Details**: Three tests in tests/audit.bats fail on unmodified feat/chezmoi on this Mac: 'ignores intentional test secret fixtures' (line 141), 'passes root artifact check in clean repo' (line 195), 'exits 0 when no failures' (line 252). Each expects exit 0, but dotfiles-audit exits 1 because machine-dependent checks (curl/jq/python shim symlinks, PATH resolution) fail inside the fake dotfiles dir. The tests should stub or skip those environment checks.
  - **Files**: tests/audit.bats,bin/dotfiles-audit
  - **Acceptance**: bats tests/audit.bats passes on this Mac with no machine-specific skips added to production code
- [ ] Make `bin/git` verify the git it selects actually runs, not just that it is executable
  - **ID**: git-wrapper-verify-selected-git-runs
  - **Tags**: scout, git, wrapper, resilience, endpoint-security
  - **Details**: `bin/git` resolves the real git by testing `[ -x /usr/bin/git ]` and preferring that path, falling back to a PATH scan only when the file is absent. An unaccepted Xcode licence leaves `/usr/bin/git` present and executable but failing on every invocation, so the wrapper kept selecting a git that could not run while a healthy Homebrew git 2.55.0 sat at `/opt/homebrew/bin/git`. Result: `git` was broken in the login shell even though a working git was installed, and `git --version` in a shell with `/opt/homebrew/bin` ahead of `/usr/bin` succeeded — making the failure look intermittent and environment-dependent. Harden the resolver to probe the candidate (for example `"$cand" --version >/dev/null 2>&1`) before committing to it, and fall through to the next candidate when the probe fails. Keep `DOTFILES_REAL_GIT` as the explicit override and do not change wrapper behaviour for the healthy case.
  - **Files**: bin/git, tests/git-wrapper.bats
  - **Acceptance**: (1) with a stub `/usr/bin/git` that exits non-zero, `bin/git --version` still succeeds via the next candidate; (2) with all candidates healthy the selected git is unchanged from today; (3) `DOTFILES_REAL_GIT` still wins when set and executable; (4) bats covers all three.

- [ ] Install `coreutils` so hook timeout wrappers stop falling back to `perl alarm`
  - **ID**: brewfile-add-coreutils-for-gtimeout
  - **Tags**: scout, brewfile, hooks, tooling
  - **Details**: `bin/dotfiles-doctor`, `bin/morning`, and agentbrew `hooks/checks/a-pr-is-not-ready.sh` pick their timeout mechanism in the order `gtimeout` → `timeout` → `perl alarm` → none. Neither `gtimeout` nor `timeout` is installed on this machine (`coreutils` is absent from the inline Brewfile), so every timeout-bounded hook takes the `perl alarm` branch. That branch is correct and was verified to bound at its configured limit, so this is not a correctness bug — but it is an undeclared dependency on system perl for a path the code clearly intends to run under coreutils, and the last fallback (`timeout_cmd=""`) removes the bound entirely. Add `coreutils` to the inline Brewfile so the intended branch is the one that runs.
  - **Files**: .chezmoiscripts/run_onchange_brew.sh.tmpl, modules/tools/doctor.sh
  - **Acceptance**: (1) `command -v gtimeout` succeeds after `dotfiles apply` on a fresh machine; (2) `make check` still passes; (3) no behaviour changes other than which timeout binary is selected.

- [ ] Workspace doctor slice 2 — consume the live tasks-md workspaces config + bootstrap flags
  - **ID**: workspace-doctor-config-integration
  - **Tags**: scout, doctor, workspace, multi-workspace, reuse, upstream
  - **Details**: Slice 1 (task `workspace-folder-doctor`, shipped 2026-06-12) landed `lib/workspace-discovery.sh` (json → yaml → sentinel/structure scan), `bin/dotfiles-workspace status`, and `modules/workspace/doctor.sh` — with the fallback scan authoritative because `~/.config/tasks-md/workspaces.{json,yaml}` does not exist on this host yet. The tasks.md `tasks workspaces add` command has shipped (tasks.md README "Workspaces") the config writer (`tasks workspaces add`), verify the json reader against the real spec shape, prefer the config end-to-end, and add the deferred bootstrap-flag checks (e.g. repos declared in the tooling workspace should be git checkouts; minsky-observed repos should carry `.minsky/repo.yaml`). This is also the Replace?/Relocate? review required by AGENTS.md rule #0 for the new module: decide whether discovery should relocate into the tasks-md CLI (`tasks workspaces list --porcelain` consumed by dotfiles) or stay a dotfiles lib, and record the decision.
  - **Files**: lib/workspace-discovery.sh, modules/workspace/doctor.sh, bin/dotfiles-workspace, tests/workspace-doctor-discovery.bats, docs/workspace.md
  - **Acceptance**: (a) discovery against a real `tasks workspaces add`-written config passes a new bats case pinning the spec shape; (b) bootstrap-flag checks land or are explicitly rejected with a reason in docs/workspace.md; (c) the Replace/Relocate decision (upstream `tasks` CLI vs dotfiles lib) is recorded in docs/workspace.md with a one-line rationale.

- [ ] Reconcile docs/module-reference.md with every doctor module
  - **ID**: module-reference-reconcile
  - **Tags**: scout, docs, drift, doctor
  - **Details**: docs/module-reference.md drifts from `modules/*/doctor.sh`. As of 2026-10-15 these modules have no section: chezmoi, local-ai, local-bin, local-llm, minsky, obsidian, personal-machine, resilience, vscode.
  - **Files**: docs/module-reference.md, modules/*/doctor.sh
  - **Acceptance**: every `modules/<name>/doctor.sh` has a matching `### <name>` section in docs/module-reference.md; module totals stay out of prose (use `make count` when needed); `bats tests/verify-counts.bats` exits 0.

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

- [ ] The `gh api -f body=` human-context test checks its assertion in an isolated env
  - **ID**: gh-wrapper-human-context-test-env-isolation
  - **Tags**: gh-wrapper, tests, false-positive, scout
  - **Details**: Two of the three human-context tests in `tests/gh-wrapper.bats` already run under `env -u` (lines ~459 and ~491). The `gh api -f body= leaves human-authored text unchanged` test (~594) still has a mid-test `! grep` with no env isolation, so an agent-context variable such as `CLAUDE_CODE_SSE_PORT` can make it pass for the wrong reason.
  - **Files**: tests/gh-wrapper.bats
  - **Acceptance**: the test fails cleanly when `CLAUDE_CODE_SSE_PORT` is set without isolation, and passes after it runs under `env -u` (or the `! grep` becomes the last assertion).
- [ ] Manage Node upgrade steps so LaunchAgents and ~/.local/bin move together
  - **ID**: dotfiles-launchagent-node-version-sprawl
  - **Tags**: scout, dotfiles, launchagent, node, permissions, mcp
  - **Details**: Scouted 2026-06-10, narrowed 2026-10-12. Done: every `com.agentbrew.*` plist now runs the Node that `~/.node-version` names, and dotfiles doctor check `agentbrew.launchagent_node_pinned` reports any plist or `~/.local/bin/node` link that drifts. Finding: `exec()` resolves symlinks, so no version-independent path (fnm alias, `~/.local/bin/node` link) can hide a Node upgrade from macOS; at best each deliberate upgrade prompts once. Not verified against a live macOS prompt. Remaining: `~/.node-version` and the `~/.local/bin/{node,npm,npx}` links are hand-made, and plists are rewritten only by a manual `agentbrew auto-sync install`.
  - **Files**: chezmoi-managed `~/.node-version` and `~/.local/bin` Node links and the upgrade flow (`bin/dotfiles-upgrade`); agentbrew `src/sync/scheduler-paths.ts` and `src/memory/launchagent.ts` rewrite the plists.
  - **Acceptance**: A Node upgrade through the dotfiles upgrade flow updates `~/.node-version`, the `~/.local/bin` links, and rewrites the agentbrew plists in one step, and `agentbrew.launchagent_node_pinned` stays green after it. The pinned minsky Node and other old fnm versions stay installed.
  - **Hypothesis**: A single scripted upgrade step removes the manual drift window between the new Node and old plists.
  - **Success**: After an upgrade, `agentbrew.launchagent_node_pinned` passes without manual steps and macOS shows at most one new Node prompt.
  - **Pivot**: If macOS still prompts on every tick with one stable path, move scheduler probes behind non-socket fast-tier probes or a pre-approved signed wrapper binary.
  - **Measurement**: `dotfiles-doctor` reports `agentbrew.launchagent_node_pinned` as passing right after an upgrade; `ps -axo command | grep '/fnm/node-versions/.*/node'` during a scheduler tick shows one versioned path.
  - **Anchor**: dotfiles PR 54 (drift check); 2026-06-10 scheduler tick diagnosis.

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

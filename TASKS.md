# Tasks

<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

## P0

- [ ] `self-metrics-competitive-benchmark` — cover dotfiles with metrics whose north star is measurably beating competitor dotfile/env-management frameworks
  - **ID**: self-metrics-competitive-benchmark
  - **Tags**: p0, operator-directive, metrics, competitive, foundational
  - **Competitive-goal**: this task IS the scorecard that defines every other task's competitive justification (self-referential bootstrap).
  - **Details**: Operator directive 2026-05-16 (fleet-wide, mirrored from minsky). Define how to measure dotfile-framework performance (fresh-machine bootstrap time, drift-detection latency, cross-machine reproducibility %, manual-step count, secret-rotation MTTR); measure dotfiles AND competitors (chezmoi, yadm, GNU stow, nix home-manager, dotbot) on the same fresh-VM workload; automate the comparison into one scorecard surfaced as the MAIN metric; require every TASKS.md task to state which competitive metric it advances. First 1-2 agent iterations on this repo establish/refresh the baseline before other work.
  - **Files**: `scripts/benchmark-*.sh`, `docs/competition/*`, `TASKS.md` (policy line), `tests/`
  - **Acceptance**: (1) cited metric set; (2) competitor corpus ≥4; (3) automated scorecard JSON + doc; (4) every new task carries a competitive-goal rationale; (5) first-iterations-bootstrap rule documented.
  - **Hypothesis**: today dotfiles has no measured comparison to peer frameworks; after this every change is steered by a live scorecard and the bootstrap-time / reproducibility gap vs the best competitor closes monotonically.
  - **Success**: the scorecard JSON reports at least 5 shared metrics for dotfiles and at least 4 competitors, from one command.
  - **Pivot**: If competitors cannot run the same fresh-VM workload inside the budget, measure dotfiles' own trend only and record why the comparison is blocked.
  - **Measurement**: `bash scripts/benchmark-run.sh --json` → `{dotfiles:{…}, competitors:[≥4]}` on ≥5 shared metrics.
  - **Anchor**: Forsgren/Humble/Kim *Accelerate* 2018 (outcome metrics not vanity); Basili/Caldiera/Rombach 1994 (Goal-Question-Metric); operator directive 2026-05-16.

- [ ] `minsky-worker-host-config-durable` — own, durably, the host/launchd config minsky currently patches in-session so its operator machine-utilisation budget is reachable on a fresh machine without one-off hacks
  - **ID**: minsky-worker-host-config-durable
  - **Tags**: p0, operator-directive, launchd, host-config, cross-repo-sync, mirrored-from-minsky
  - **Competitive-goal**: a fresh machine reproducing the correct minsky worker host-config in one `dotfiles` apply (vs manual in-session plist surgery) is the reproducibility-% and manual-step-count metric on the dotfiles scorecard.
  - **Details**: operator directive 2026-05-17 (filed from minsky per its vision.md rule #15 "match the operator machine-utilisation budget" + rule #1 "don't hand-maintain what a managed repo should own"). Minsky's worker launchd unit (`com.minsky.opus-sonnet-run`) was being hand-edited per session; make these durable here so minsky pulls them: (a) **`ProcessType=Standard`** for any minsky worker launchd unit — `Background` imposes macOS QoS CPU/IO throttling that makes a high-utilisation budget physically unreachable; (b) raise `ulimit -n` / `maxfiles` for high worker fan-out (dozens of node procs + git worktrees); (c) pin the worker node version consistently (the launchd unit and the interactive shell must agree — a v24.14.0/v24.15.0 split silently broke biome/lefthook hooks); (d) provision the arch-correct toolchain binary path (`BIOME_BINARY` → an arm64 biome on Apple Silicon) so commits/hooks work headless. Provide a template/managed launchd plist + a `ulimit`/`maxfiles` LaunchDaemon or login hook + the node-pin + the biome-binary provisioning, so `dotfiles apply` yields a host where the minsky budget is reachable with zero in-session edits.
  - **Files**: `launchd/` (managed `com.minsky.opus-sonnet-run` template incl. `ProcessType=Standard`), `limits/` (nofile/maxfiles), node-version pin (`.tool-versions`/fnm), `install/` (arm64 biome provisioning), `TASKS.md`.
  - **Hypothesis**: today reproducing a correct minsky worker host requires manual plist/ulimit/node/biome surgery every session; after this a single `dotfiles apply` produces it, manual-step-count for "bring up a minsky swarm host" drops to ~0.
  - **Acceptance**: `dotfiles apply` on a fresh Apple-Silicon host yields a launchd unit with `ProcessType=Standard`, raised nofile, pinned node, working `BIOME_BINARY`; minsky pulls these instead of patching them; documented in the repo README.
  - **Success**: a clean Apple-Silicon VM reaches a working minsky worker host after one `dotfiles apply`, with 0 manual host-config steps.
  - **Pivot**: If a step needs admin rights that `dotfiles apply` must not take, document it as a single `needs-user-action` step and stop there.
  - **Measurement**: count manual host-config steps to bring up a minsky swarm host before vs after (target: from ~5 to 0); reproduce on a clean VM.
  - **Anchor**: operator directive 2026-05-17; minsky vision.md rule #15 (operator machine-utilisation budget) + rule #1 (propagate to the managed repo); Apple `launchd.plist(5)` (`ProcessType` QoS). Mirrored from minsky `operator-machine-budget-autoscale`.

## P1

<!-- COHORT: github-issues-task-backend (2026-05-29 operator directive). Shell-level
     ergonomics for the GitHub Issues task backend so filing/claiming a task from a
     terminal (or a personal machine) is as fast as editing TASKS.md was. Blocks on
     agentbrew `ghi-gh-issues-helper`. Origin: a task-backend RFC. -->

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

- [ ] Multi-task overnight grind harness (run for hours, log success rate)
  - **ID**: local-ai-loop-overnight-grind
  - **Tags**: local-ai, automation, overnight
  - **Details**: Today's 3 P0 completions ran one-at-a-time via
    `./bin/local-ai-loop --max-tasks 1`. The next stretch is to
    let the loop run for hours from a queue of pre-seeded P0 tasks
    and measure per-task success / wall time / regression rate.
    Wire `local-ai-loop` to (a) read a `tasks-queue/` directory of
    one-task-per-file specs, (b) launch each as its own dogfood
    branch, (c) merge or revert per-task based on the reviewer
    gate from `local-ai-loop-pre-merge-reviewer`, (d) accumulate a
    summary CSV alongside `docs/audits/local-ai-runs.csv`. Target:
    8h unattended, 80%+ P0 completion rate.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py,
    docs/local-ai-roadmap.md
  - **Acceptance**: `./bin/local-ai-loop --queue tasks-queue/`
    runs N tasks back-to-back, opens N PRs (or N rollback notes),
    writes a summary line per task to `docs/audits/local-ai-runs.csv`.
    Documented in `docs/local-ai-roadmap.md`.
  - **Hypothesis**: Running queued local-ai tasks for hours will expose success-rate and rollback failure modes not visible in one-task tests.
  - **Success**: An 8h run completes >=80% of seeded P0 tasks or records rollback notes for failures.
  - **Pivot**: If success rate is below 80%, pause feature expansion and fix the top recurring failure in the run CSV.
  - **Measurement**: `./bin/local-ai-loop --queue tasks-queue/` writes one summary CSV row per task with status/wall-time/regression outcome.
  - **Anchor**: docs/local-ai-roadmap.md local-agent hardening; docs/user-stories/09-run-local-models-fast.md.

- [ ] Stretch the loop to genuine feature work (patch_file in anger)
  - **ID**: local-ai-loop-feature-work-dogfood
  - **Tags**: local-ai, dogfood, patch_file
  - **Details**: All 3 P0 deliverables today were "static surface
    tests" — new bats files exercising `[ -x bin/... ]` /
    shebang / set-flag. The harder shape is editing an existing
    file via `patch_file` (no successful real-world `patch_file`
    use yet). Promote a P2 to P0 — best candidate is
    `doctor-opencode-tools-auto-fix` (modifies the existing
    `modules/local-ai/doctor.sh`, adds a fix-mode helper). Run the
    loop; observe where `patch_file` breaks; ship a follow-up that
    closes the failure modes.
  - **Files**: modules/local-ai/doctor.sh,
    tests/module-local-ai-opencode-fix.bats
  - **Acceptance**: At least one task that modifies an existing
    file > 100 lines via `patch_file` completes end-to-end. New
    failure modes captured in
    `docs/audits/local-ai-failure-modes.md`.
  - **Hypothesis**: Forcing local-ai-loop to patch an existing >100-line file will reveal real edit-path failures hidden by static test tasks.
  - **Success**: At least one existing-file modification task completes end-to-end with correct tests and failure-mode notes updated.
  - **Pivot**: If patch_file remains unreliable, add a smaller patching harness before using the loop on feature work.
  - **Measurement**: Chosen task modifies `modules/local-ai/doctor.sh`, passes `make check`, and records observed failures in docs.
  - **Anchor**: docs/audits/local-ai-failure-modes.md; docs/user-stories/09-run-local-models-fast.md.

- [ ] Bridge `local-ai-loop` into `taskgrind` as a sub-runner
  - **ID**: integrate-local-ai-loop-with-taskgrind
  - **Tags**: local-ai, taskgrind, integration
  - **Details**: Currently `local-ai-loop` is a standalone driver
    that reads TASKS.md directly. `taskgrind` (in
    `~/apps/experiments/taskgrind/`) is the larger task-runner that
    already understands queue ordering, retries, and worktree
    isolation. Wire it so `taskgrind` dispatches "cheap, single-
    file" tasks (tagged `local-ai-ok` or matching a complexity
    heuristic) to `local-ai-loop` instead of the default
    cloud-backed runner. The two repos already share TASKS.md
    syntax. Cost cap: `taskgrind --budget local-ai` should route
    everything tagged `local-ai-ok` through qwen3-coder:30b for
    free.
  - **Files**: ~/apps/experiments/taskgrind/lib/, lib/local-ai-loop.py
  - **Acceptance**: A `taskgrind` invocation in any repo with
    `local-ai-ok`-tagged tasks routes them through
    `local-ai-loop` and merges PRs identically. Documented in
    `docs/local-ai-roadmap.md`.
  - **Hypothesis**: Routing cheap tagged work through local-ai-loop can reduce cloud-agent cost while preserving taskgrind queue semantics.
  - **Success**: `taskgrind --budget local-ai` delegates `local-ai-ok` tasks and produces the same merge/rollback artifacts.
  - **Pivot**: If taskgrind integration duplicates Minsky/agentbrew orchestration, expose local-ai-loop as a generic runner API instead.
  - **Measurement**: A fixture repo with a `local-ai-ok` task routes through local-ai-loop in tests and documents the flow.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

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
    `~/apps/agentbrew/skill-plugins/dev/local-ai-loop/` so other
    repos can opt-in via `agentbrew sync`. Validate on
    `agentbrew/` and `dotfiles-<org>/`.
  - **Files**: bin/local-ai-loop, lib/local-ai-loop.py,
    .local-ai-loop.json (new), ~/apps/agentbrew/skill-plugins/
  - **Acceptance**: `local-ai-loop` runs successfully from at
    least 2 different repos (dotfiles + one other), each with its
    own `.local-ai-loop.json`. Original dotfiles flow still works.
  - **Hypothesis**: Extracting repo-specific local-ai-loop config lets the runner work beyond dotfiles without hardcoded make/bats assumptions.
  - **Success**: The loop completes a task in dotfiles and one other repo using per-repo `.local-ai-loop.json` configs.
  - **Pivot**: If cross-repo differences are too large, keep dotfiles as the only supported repo and document required adapter hooks.
  - **Measurement**: `local-ai-loop` fixture tests cover two config files and both runs reach verification.
  - **Anchor**: docs/local-ai-roadmap.md; docs/user-stories/09-run-local-models-fast.md.

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

- [ ] Add the `tests/chezmoi.bats` regression assertions for the `.chezmoiignore` repo entries
  - **ID**: chezmoiignore-repo-files-leak-to-home-root
  - **Tags**: chezmoi, dotfiles-apply, bug, regression, scout
  - **Details**: Status 2026-09-28: the `.chezmoiignore` entries landed, and the live Measurement reads 0. Only the matching `[ ! -e "$TEST_HOME/<name>" ]` assertions in `tests/chezmoi.bats` remain; none exist yet. Original report: `.chezmoiignore` is missing repo entries for `ARCHITECTURE.md`, `ROADMAP.md`, `VISION.md`, `agent-hooks`, `commands`, `scripts`, `templates`, `vscode`, and `windsurf`, so `chezmoi apply` currently deploys these repo files/dirs to `$HOME` root on every apply. Confirmed live 2026-09-17: `chezmoi managed --path-style absolute` lists each as a managed target directly under `$HOME`. Fix: add those paths to `.chezmoiignore` under a new comment block (`# Repo files/dirs that must never deploy to $HOME (were leaking to ~ root)`), and extend the existing deploy-target regression test in `tests/chezmoi.bats` (the block asserting `[ ! -e "$TEST_HOME/launchagents" ]` etc.) with matching `[ ! -e "$TEST_HOME/<name>" ]` assertions for every listed name.
  - **Files**: .chezmoiignore, tests/chezmoi.bats
  - **Acceptance**: `chezmoi managed --path-style absolute` (after a clean apply) lists none of those repo paths under `$HOME` top level; `bats tests/chezmoi.bats` exits 0 including the new regression assertions.
  - **Hypothesis**: Adding the missing entries to `.chezmoiignore` stops repo files from deploying to `$HOME` root.
  - **Success**: `chezmoi managed --path-style absolute` shows none of the listed repo paths under `$HOME` top level after apply.
  - **Pivot**: If entries still leak after the ignore-list edit, the deploy path isn't `.chezmoiignore`-driven for those types (e.g. symlink vs copy mode) — inspect chezmoi source-attribute prefixes instead of extending the ignore list further.
  - **Measurement**: `chezmoi managed --path-style absolute | grep -c -E '^/Users/[^/]+/(ARCHITECTURE\.md|ROADMAP\.md|VISION\.md|agent-hooks|commands|scripts|templates|vscode|windsurf)$'` reads 0.
  - **Anchor**: chezmoi source/target separation (chezmoi `.chezmoiignore` docs); dotfiles rule "never deploy repo files to $HOME".

## P2

- [ ] Prevent dotfiles-sync from stopping its own active run during a LaunchAgent reload
  - **ID**: dotfiles-sync-self-reload-safe
  - **Tags**: launchagents, sync, resilience, doctor
  - **Details**: `dotfiles-sync` can repair or reload `com.dotfiles.dotfiles-sync` while that same job is running. A bootstrap or kickstart can terminate the active run before it finishes its remaining apply and health checks. Preserve a completed active run, then schedule a subsequent sync when a reload is necessary.
  - **Files**: bin/dotfiles-sync, bin/dotfiles-reload-launchagents, tests/
  - **Acceptance**: a fixture that requests its own reload completes its current sync path and records one follow-up reload or sync without duplicate concurrent work.

- [ ] Recover stale dotfiles sync locks without waiting for a future scheduled sync
  - **ID**: dotfiles-sync-stale-lock-recovery
  - **Tags**: lock, sync, doctor, resilience
  - **Details**: A stale sync lock from PID 79025 blocked `dotfiles-doctor --fix` until a later scheduled sync. Detect a dead lock owner, remove only that stale lock, and keep a live owner protected.
  - **Files**: lib/lock.sh, bin/dotfiles-sync, bin/dotfiles-doctor, tests/
  - **Acceptance**: tests distinguish a live owner from a nonexistent PID; doctor can recover from the latter and leaves the former untouched.

- [ ] Mark `~/.agent-browser` private in chezmoi so a non-interactive apply does not stop
  - **ID**: chezmoi-agent-browser-private-dir
  - **Tags**: chezmoi, dotfiles-apply, agent-browser, security
  - **Details**: The source directory is `dot_agent-browser`, so chezmoi wants mode 0755. agent-browser keeps the folder at 0700 because it holds `.encryption-key` and browser profiles. After that, `chezmoi status` shows `MM .agent-browser`, and `dotfiles apply` without a TTY stops with ".agent-browser has changed since chezmoi last wrote it?" and "could not open a new TTY" (seen 2026-09-28). An apply with a TTY or `--force` loosens the folder to 0755. Fix: rename `dot_agent-browser` to `private_dot_agent-browser`, so chezmoi's target mode is 0700, and update every path reference to the old name.
  - **Files**: dot_agent-browser/ (rename), TASKS.md and docs that cite `dot_agent-browser/`, tests/chezmoi.bats
  - **Acceptance**: (1) after a clean apply, `~/.agent-browser` is 0700; (2) `chezmoi status ~/.agent-browser` prints nothing; (3) `dotfiles apply </dev/null` does not prompt for this folder; (4) bats asserts the 0700 mode.
  - **Hypothesis**: The prompt comes only from the mode mismatch between the source (0755) and agent-browser's own 0700. A private source attribute makes both 0700 and takes non-TTY apply stops on this folder from 1 per apply to 0.
  - **Success**: The Measurement prints `700` and no `.agent-browser` status line.
  - **Pivot**: If agent-browser starts to need group or other read access, keep 0755 in the source and stop agent-browser from tightening the folder instead.
  - **Measurement**: `stat -f %Lp ~/.agent-browser; chezmoi status ~/.agent-browser`
  - **Anchor**: chezmoi reference, "Source state attributes" (`private_` sets 0700 on directories); Saltzer & Schroeder, "The Protection of Information in Computer Systems", 1975 (least privilege).

- [ ] Deprecate Windsurf and Augment; focus on Claude Code, WebStorm and Cursor
  - **ID**: deprecate-windsurf-augment-agents
  - **Tags**: agentfile, agents, deprecation, windsurf, augment, cleanup
  - **Details**: Owner decision 2026-09-28: Windsurf and Augment are deprecated. The focus tools are Claude Code (also in the WebStorm terminal), WebStorm and Cursor; a machine can still opt out of Cursor with `use_cursor: false`. Today dotfiles still lets agentbrew detect and sync windsurf, because the merged global Agentfile excludes only `cursor` (through `config/agentfile-no-cursor.yaml`). It also runs `modules/windsurf/doctor.sh` (2 doctor failures on a Mac without Windsurf) and links `windsurf/` settings and keybindings into `~/Library/Application Support/Windsurf/User`. On 2026-09-28, removing `~/.codeium/windsurf` by hand did not stick: the next `agentbrew sync --pull` recreated it. Steps: (1) exclude `windsurf` and `augment` on every machine: add them to `excludeAgents` in the base `Agentfile.yaml`, or add an always-merged `config/agentfile-deprecated-agents.yaml` in `.chezmoiscripts/run_after_agentbrew-sync.sh`; (2) retire `modules/windsurf` and the `windsurf/` settings, and remove the links they created; (3) state the focus tools in README; (4) once agentbrew cleans up excluded agents (agentbrew task `agents-deprecated-flag-and-exclude-cleanup`), confirm `~/.codeium/windsurf` is gone after apply.
  - **Files**: Agentfile.yaml or config/agentfile-deprecated-agents.yaml, .chezmoiscripts/run_after_agentbrew-sync.sh, modules/windsurf/, windsurf/, README.md, tests/
  - **Acceptance**: (1) the merged `~/.config/agentbrew/Agentfile.yaml` excludes `windsurf` and `augment` on every machine; (2) doctor runs no windsurf checks; (3) no dotfiles link points into `~/Library/Application Support/Windsurf`; (4) bats covers the merged exclusion.
  - **Hypothesis**: Windsurf still gets synced config and doctor noise only because dotfiles never excludes it. Excluding it takes detected deprecated agents from 1 (windsurf) to 0 and windsurf doctor failures from 2 to 0.
  - **Success**: The Measurement lists `windsurf` and `augment` under `excludeAgents`, and the detected-agent line does not name windsurf.
  - **Pivot**: If some machine still needs Windsurf, move the exclusion to a per-machine chezmoi flag (like `use_cursor`) instead of the base Agentfile.
  - **Measurement**: `yq '.excludeAgents' ~/.config/agentbrew/Agentfile.yaml; agentbrew status --verbose 2>&1 | grep -i -c windsurf`
  - **Anchor**: Fowler, "ParallelChange", martinfowler.com, 2014 (deprecate, migrate, then remove in separate steps).

- [ ] Cut doctor failures on a converged personal Mac from 43 to the ones that need action
  - **ID**: doctor-converged-mac-failure-triage
  - **Tags**: scout, doctor, noise, triage
  - **Details**: A full `dotfiles doctor` right after a clean apply on 2026-09-28 reported 477 passed, 43 failed, 18 warned, 5 skipped. Groups: (a) 18 VS Code checks (`code` CLI plus 17 extensions) and 2 Windsurf checks on a Mac where neither app is installed; (b) 4 power checks (AC system sleep, AC disk sleep, AC idle timers, Amphetamine preferences) that fail while an agent session is running; (c) Obsidian vim mode and `opencode-serve` on :4096 (apps not in use); (d) owned failures that need a fix: agentbrew memory LaunchAgent PATH resolves `jq`, `ggrep`, `curl` and `perl` outside `dotfiles/bin` (4); memory LaunchAgent plist path and HOME (1); global Agentfile does not match the dotfiles/overlay merge (1); Devin config default model (1); (e) other owners: 6 minsky `bin/` scripts use `#!/usr/bin/env` (minsky repo), and Node-backed LaunchAgents are disabled while the publisher is blocked (see the endpoint-policy task above). Steps: make group (a) and (c) checks skip when the app is not installed; make group (b) report "skipped: agent running" instead of failing; fix group (d); file group (e) in the owning repo.
  - **Files**: modules/vscode/doctor.sh, modules/windsurf/doctor.sh, modules/resilience/doctor.sh, modules/obsidian/doctor.sh, the agentbrew memory LaunchAgent template, TASKS.md
  - **Acceptance**: (1) on a Mac without VS Code or Windsurf, those checks report skipped, not failed; (2) power checks report skipped while an agent runs; (3) each group (d) check passes after `dotfiles doctor --fix`; (4) each group (e) item has a task in its owning repo.
  - **Hypothesis**: Most doctor failures on a converged Mac are checks for absent apps or for state that an agent session causes on purpose, and they hide the few real failures. Skipping those and fixing group (d) takes failures from 43 to at most 8 (group (e) and anything new).
  - **Success**: The Measurement prints 8 or fewer on the same Mac, right after a clean apply.
  - **Pivot**: If skipping hides a real failure (an installed app whose check now reports skipped), revert the skip for that module and use a warning level instead.
  - **Measurement**: `dotfiles doctor </dev/null 2>&1 | grep -oE '✗ [0-9]+ failed' | grep -oE '[0-9]+'` (baseline 2026-09-28: 43).
  - **Anchor**: Beyer et al., *Site Reliability Engineering*, 2016, Ch. 6 "Monitoring Distributed Systems" (every alert must be actionable; noise trains people to ignore alerts).

- [ ] Make `chezmoi init --no-tty` work on a configured machine — it stops at the `morning_hour` prompt
  - **ID**: chezmoi-init-no-tty-promptintonce-reprompt
  - **Tags**: scout, chezmoi, init, config, resilience
  - **Details**: After a `.chezmoi.yaml.tmpl` change, chezmoi warns `config file template has changed, run chezmoi init`. On 2026-09-27, `chezmoi init --no-tty` then failed with `error calling promptIntOnce: EOF` at `promptIntOnce . "morning_hour"`, even though `~/.config/chezmoi/chezmoi.yaml` already had `morning_hour: 8`. The `*Once` prompts should return the stored value, so something in how the int is read back is wrong. Until it is fixed, the only non-interactive path is passing each int by its prompt text (`--promptInt 'Morning briefing hour (0-23)=8'`), which agents will not know. `chezmoi init` also drops hand-written comments in the generated config (a `brew_skip` note was lost), so notes like that belong in the template or docs.
  - **Files**: .chezmoi.yaml.tmpl, tests/chezmoi.bats
  - **Acceptance**: (1) with an existing config that sets `morning_hour` and `morning_minute`, `chezmoi init --no-tty` exits 0 and keeps both values; (2) a fresh init still prompts for them; (3) bats covers both cases.

- [ ] Clean up LaunchAgents left from an earlier username prefix
  - **ID**: launchagents-cleanup-legacy-username-prefix
  - **Tags**: scout, launchagents, cleanup, resilience
  - **Details**: The personal Mac still loads LaunchAgents whose label uses an old username prefix instead of `com.dotfiles.` — `<old-prefix>.cursor-priority`, `<old-prefix>.dotfiles-sync`, and `<old-prefix>.dotfiles-doctor` — next to their `com.dotfiles.*` replacements. The legacy doctor exits 1 on every run, and each pair does the same job twice. The orphan unload in `.chezmoiscripts/run_onchange_launchagents.sh.tmpl` only scans `com.dotfiles.*`, so it never sees these. Find them by `ProgramArguments` that point into the dotfiles `bin/`, not by a hard-coded username.
  - **Files**: .chezmoiscripts/run_onchange_launchagents.sh.tmpl, modules/launchagents/doctor.sh (or the nearest existing module), tests/launchagents.bats
  - **Acceptance**: (1) a doctor check fails when a non-`com.dotfiles.*` LaunchAgent runs a dotfiles `bin/` script that a `com.dotfiles.*` agent already covers; (2) its fix unloads and removes that plist; (3) unrelated third-party LaunchAgents are never touched; (4) bats covers all three with a fake `~/Library/LaunchAgents`.
- [ ] Replace? Relocate: update-tooling orchestration
  - **ID**: replace-relocate-update-tooling-orchestration
  - **Tags**: scout, tooling, agentbrew, dotfiles, reuse, upstream
  - **Details**: The `update-tooling` skill currently coordinates safe primary-checkout refresh, the chezmoi applied checkout, agentbrew sync and health checks, and task ranking. Re-evaluate whether a maintained upstream tool can own more of this workflow without losing the local ownership boundary: dotfiles owns the host and Agentfile; agentbrew owns generated agent configuration. Prefer a pointer or thin adapter when an upstream workflow can preserve fast-forward-only Git behavior, applied-checkout safety, and non-destructive task recommendations.
  - **Files**: skills/update-tooling/SKILL.md, Agentfile.yaml, README.md
  - **Acceptance**: Record one current decision in the skill or README: replace with an upstream tool, relocate a portion to agentbrew or chezmoi, or keep the skill with a specific local-only reason. If a maintained upstream covers the workflow, remove duplicated guidance and point to that source.

- [ ] Detect an unaccepted Xcode CLT license in doctor — it silently breaks git, python3, clang and make
  - **ID**: doctor-detect-unaccepted-xcode-license
  - **Tags**: scout, doctor, xcode, clt, git, resilience
  - **Details**: On 2026-09-18 every Command Line Tools-backed binary on this machine exited non-zero with `You have not agreed to the Xcode license agreements. Please run 'sudo xcodebuild -license'`. That silently took out `git`, `python3`, `clang` and `make` at once: `make check` could not run, every `git` command in the login shell died, and a YAML-parse helper using `python3` produced false failures that read like real defects. Nothing in `dotfiles doctor` health checks reported it, so the cause took a full debugging detour to find. The condition is trivially detectable (`/usr/bin/git --version` exits non-zero and its stderr matches `Xcode license`) and the repair is a single documented operator command. Add a check that names the exact fix, and treat it as needs-user-action rather than auto-fixing, because accepting a licence requires `sudo` and human agreement.
  - **Files**: modules/xcode/doctor.sh (new) or modules/security/doctor.sh, tests/module-xcode-doctor.bats
  - **Acceptance**: (1) the check fails, with the `sudo xcodebuild -license accept` remedy in its message, when the licence is unaccepted; (2) it passes once accepted; (3) it is marked needs-user-action and never attempts `sudo` itself; (4) bats covers both branches with a stubbed `xcodebuild`/`git`.

- [ ] Make `bin/git` verify the git it selects actually runs, not just that it is executable
  - **ID**: git-wrapper-verify-selected-git-runs
  - **Tags**: scout, git, wrapper, resilience, endpoint-security
  - **Details**: `bin/git` resolves the real git by testing `[ -x /usr/bin/git ]` and preferring that path, falling back to a PATH scan only when the file is absent. An unaccepted Xcode licence leaves `/usr/bin/git` present and executable but failing on every invocation, so the wrapper kept selecting a git that could not run while a healthy Homebrew git 2.55.0 sat at `/opt/homebrew/bin/git`. Result: `git` was broken in the login shell even though a working git was installed, and `git --version` in a shell with `/opt/homebrew/bin` ahead of `/usr/bin` succeeded — making the failure look intermittent and environment-dependent. Harden the resolver to probe the candidate (for example `"$cand" --version >/dev/null 2>&1`) before committing to it, and fall through to the next candidate when the probe fails. Keep `DOTFILES_REAL_GIT` as the explicit override and do not change wrapper behaviour for the healthy case.
  - **Files**: bin/git, tests/git-wrapper.bats
  - **Acceptance**: (1) with a stub `/usr/bin/git` that exits non-zero, `bin/git --version` still succeeds via the next candidate; (2) with all candidates healthy the selected git is unchanged from today; (3) `DOTFILES_REAL_GIT` still wins when set and executable; (4) bats covers all three.

- [ ] Install `coreutils` so hook timeout wrappers stop falling back to `perl alarm`
  - **ID**: brewfile-add-coreutils-for-gtimeout
  - **Tags**: scout, brewfile, hooks, tooling
  - **Details**: `hooks/lib/claude-verifier.sh` picks its timeout mechanism in the order `gtimeout` → `timeout` → `perl alarm` → none. Neither `gtimeout` nor `timeout` is installed on this machine (`coreutils` is absent from the inline Brewfile), so every timeout-bounded hook takes the `perl alarm` branch. That branch is correct and was verified to bound at its configured limit, so this is not a correctness bug — but it is an undeclared dependency on system perl for a path the code clearly intends to run under coreutils, and the last fallback (`timeout_cmd=""`) removes the bound entirely. Add `coreutils` to the inline Brewfile so the intended branch is the one that runs.
  - **Files**: .chezmoiscripts/run_onchange_brew.sh.tmpl, modules/tools/doctor.sh
  - **Acceptance**: (1) `command -v gtimeout` succeeds after `dotfiles apply` on a fresh machine; (2) the Brewfile audit workflow still passes; (3) no hook behaviour changes other than which timeout binary is selected.

- [ ] Stop `dotfiles update`/chezmoi apply prompting on untracked `~/.gitconfig` `[user] email` ("could not open a new TTY")
  - **ID**: chezmoi-gitconfig-email-drift-tty-prompt
  - **Tags**: scout, chezmoi, gitconfig, drift, dotfiles-update
  - **Details**: `dotfiles update` (chezmoi apply phase) exits 1 with `chezmoi: ...: could not open a new TTY` because the live `~/.gitconfig` carries a `[user]` `email = <personal-email>` block the chezmoi source does not track, so chezmoi treats it as removable drift and tries to confirm interactively — which fails headless. Two mirror-safe fixes: (a) move the live `[user] email` into `~/.gitconfig.local` (already `[include]`d, untracked) so chezmoi has nothing to reconcile — preferred; or (b) add a `.chezmoiignore`/template guard so chezmoi never manages the `[user]` block. Do NOT hardcode any personal email into a tracked file. Add a `modules/git/doctor.sh` check that fails when `~/.gitconfig` has a tracked `[user] email` conflicting with the source.
  - **Files**: dot_gitconfig.tmpl, dot_gitconfig.personal.tmpl, .chezmoiignore, modules/git/doctor.sh, tests/module-git-doctor.bats
  - **Acceptance**: (1) the `dotfiles update` apply phase exits 0 on a host whose `~/.gitconfig` previously carried an untracked `[user] email`; (2) no personal email literal is committed to any tracked source file; (3) a doctor check fails when the drift recurs; (4) `bats tests/module-git-doctor.bats` exits 0.

- [ ] Pin `defaultModel: claude-opus-4-8` in `Agentfile.yaml` so Opus 4.8 is the durable default and no agent ever picks Fable
  - **ID**: pin-default-model-opus-agentfile
  - **Tags**: model-config, agentbrew, agentfile, opus, scout
  - **Details**: Operator directive 2026-06-13: "fable 5 should not be picked anywhere by default; opus 4.8 where it was fable." Applied live via `agentbrew sync` (state.yaml carries `defaultModel: claude-opus-4-8` with `modelOverrides: {devin: null, codex: null}`, and `~/.claude/settings.json` model is `claude-opus-4-8`), but the pin is NOT durable on canonical: the next sync re-derives state from the Agentfile, which lacks the key. Add the block to `Agentfile.yaml` (top level, before `hooks:`): `defaultModel: claude-opus-4-8` plus `modelOverrides:` with `devin: null` and `codex: null` (null = model-sync skips that agent, preserving the Devin gpt-5.5 / Codex OpenAI carve-outs).
  - **Files**: Agentfile.yaml
  - **Acceptance**: (1) `agentbrew sync --dry-run --agentfile Agentfile.yaml` reports "default model updated"; (2) post-sync `jq .model ~/.claude/settings.json` == `claude-opus-4-8`; (3) `~/.config/devin/config.json` `agent.model` and `~/.codex/config.toml` `model` are unchanged by the sync; (4) no `*fable*` model id appears in any synced agent config.

- [ ] Workspace doctor slice 2 — consume the live tasks-md workspaces config + bootstrap flags
  - **ID**: workspace-doctor-config-integration
  - **Tags**: scout, doctor, workspace, multi-workspace, reuse, upstream
  - **Details**: Slice 1 (task `workspace-folder-doctor`, shipped 2026-06-12) landed `lib/workspace-discovery.sh` (json → yaml → sentinel/structure scan), `bin/dotfiles-workspace status`, and `modules/workspace/doctor.sh` — with the fallback scan authoritative because `~/.config/tasks-md/workspaces.{json,yaml}` does not exist on this host yet. When the tasksmd foundation task (`workspace-mode-nested-repos`) ships the config writer (`tasks workspaces add`), verify the json reader against the real spec shape, prefer the config end-to-end, and add the deferred bootstrap-flag checks (e.g. repos declared in the tooling workspace should be git checkouts; minsky-observed repos should carry `.minsky/repo.yaml`). This is also the Replace?/Relocate? review required by AGENTS.md rule #0 for the new module: decide whether discovery should relocate into the tasks-md CLI (`tasks workspaces list --porcelain` consumed by dotfiles) or stay a dotfiles lib, and record the decision.
  - **Files**: lib/workspace-discovery.sh, modules/workspace/doctor.sh, bin/dotfiles-workspace, tests/workspace-doctor-discovery.bats, docs/workspace.md
  - **Acceptance**: (a) discovery against a real `tasks workspaces add`-written config passes a new bats case pinning the spec shape; (b) bootstrap-flag checks land or are explicitly rejected with a reason in docs/workspace.md; (c) the Replace/Relocate decision (upstream `tasks` CLI vs dotfiles lib) is recorded in docs/workspace.md with a one-line rationale.

- [ ] Fix 4 pre-existing docs-links failures (company-fork anchors)
  - **ID**: docs-links-company-fork-anchors
  - **Tags**: scout, docs, drift, oss-readiness
  - **Details**: Found 2026-06-12 while shipping the workspace module: `bats tests/docs-links.bats --filter "local links resolve"` fails identically on the untouched canonical checkout with: README.md:169 + :177 missing anchor `#for-company-employees` (in README itself), README.md:247 missing anchor `#removing-all-organization-specific-references` in docs/forking-guide.md, README.md:313 missing local link target `docs/adoption-company.md`. These all touch company-fork content that the no-internal-refs pass (`lib/oss-readiness.sh`) may have renamed. Do NOT blind-fix: first determine whether the canonical README should link to overlay-only targets at all, then either restore the headings/files or repoint the links, keeping `tests/no-internal-refs.bats` green.
  - **Files**: README.md (lines ~169, 177, 247, 313), docs/forking-guide.md, lib/oss-readiness.sh, tests/docs-links.bats
  - **Acceptance**: `bats tests/docs-links.bats` exits 0 on the canonical checkout AND `bats tests/no-internal-refs.bats tests/oss-readiness-lib.bats` stay green.

- [ ] Reconcile docs/module-reference.md with every doctor module
  - **ID**: module-reference-reconcile-34
  - **Tags**: scout, docs, drift, doctor
  - **Details**: Found 2026-06-12 while shipping the workspace module: docs/module-reference.md's header and per-module sections drift from `modules/*/doctor.sh` — minsky, obsidian, local-ai, local-bin, local-llm, resilience, personal-machine, devin (partial), windsurf/vscode if present, and workspace's siblings are missing their `### <module> (N checks)` sections. Generate the missing sections from `modules/*/doctor.sh` check IDs + descriptions (the doc format is mechanical: ID / What it checks / Auto-fix per row). Use `make count` when a live module total is needed in prose.
  - **Files**: docs/module-reference.md, modules/*/doctor.sh
  - **Acceptance**: every `modules/<name>/doctor.sh` has a matching `### <name>` section in docs/module-reference.md; module totals stay out of prose (use `make count` when needed); `bats tests/verify-counts.bats` exits 0.

- [ ] Add `gh-cross-repo-pr-approval` Claude Code hook (agentbrew) — backstop remains in dotfiles/bin/gh
  - **ID**: gh-cross-repo-pr-approval-hook
  - **Tags**: scout, hooks, gh-wrapper, agentbrew
  - **Details**: `dotfiles-migrate-shell-wrappers-to-hooks` shipped the gh/git attribution + conventional-commit hooks. The cross-repo PR approval gate still lives only in `dotfiles/bin/gh` (`AGENT_PUBLIC_WRITE_APPROVAL` token). Port it to `agentbrew/hooks/checks/gh-cross-repo-pr-approval.sh` (PreToolUse Bash matcher on `gh pr create --repo`) so Claude Code blocks cross-repo PR create without per-session approval before the wrapper runs.
  - **Files**: `agentbrew/hooks/checks/gh-cross-repo-pr-approval.sh` (new), `agentbrew/hooks/manifest.yaml`, `dotfiles/bin/gh` (reference only — stays as shell backstop)
  - **Acceptance**: Hook fixture tests block `gh pr create --repo other/repo` without approval token; dotfiles `tests/gh-wrapper.bats` stays green.
  - **Surfaced-by**: 2026-06-11 closing `dotfiles-migrate-shell-wrappers-to-hooks` — four of five planned hooks landed; cross-repo gate deferred to agentbrew.

- [ ] dotfiles-doctor JSON mode reports "fixed" status before `_fix` actually runs
  - **ID**: doctor-json-fixed-status-leaks-on-fix-failure
  - **Tags**: scout, doctor, json, observability
  - **Details**: In `bin/dotfiles-doctor`, the `check()`, `check_symlink()`, `check_managed()`, and `check_defaults()` helpers all call `$JSON_MODE && _json_add "$id" "fixed" "$desc"` immediately after `_fix "$desc" "$fix_cmd"` returns — but `_fix` itself decides whether the fix succeeded (calls `fixed "$desc"`) or failed (calls `fail "$desc (fix failed or timed out)"`). The JSON line is written before that decision lands, so `--json --fix` runs report status `"fixed"` for checks where the fix actually failed. Internal counters `fix_count`/`fail_count` are correct because they're set by `_fix` itself — only the JSON output drifts.

    Fix: mirror the same `(( fix_count > _f0 ))` / `(( fail_count > _x0 ))` delta check that was added for `failed_check_ids`/`fixed_check_ids` tracking (in this same commit), and emit the JSON status conditionally based on which counter went up. Apply to all four `check_*` helpers consistently.
  - **Files**: `bin/dotfiles-doctor` (check, check_symlink, check_managed, check_defaults), `tests/doctor.bats` (add a "JSON status reflects actual fix outcome" test that stubs `_fix` to fail and asserts `--json` reports `"fail"` not `"fixed"`)
  - **Acceptance**: With a check whose `fix_cmd` is `false`, `bin/dotfiles-doctor --module X --fix --json` outputs `"status":"fail"` (or `"status":"fail_after_fix_attempt"`) for that check, not `"fixed"`. Bats test passes.
  - **Surfaced-by**: 2026-05-25 — investigating dotfiles-doctor notification content while adding `failed_check_ids`/`fixed_check_ids` tracking exposed the same race in the JSON emission path.

- [ ] dotfiles-doctor notification — add bats test that captures notify content via terminal-notifier stub
  - **ID**: doctor-notification-content-test
  - **Tags**: scout, doctor, tests, observability
  - **Details**: The notification now embeds top-5 failing check IDs (commit landing alongside this task). There is no automated test that the notification text actually contains the IDs — manual end-to-end verification was done by PATH-overriding `terminal-notifier` to log args. Add a bats test that:
    1. Creates a tmp `bin/terminal-notifier` stub that writes `$@` to `$BATS_TEST_TMPDIR/notify.log`
    2. Forces at least one failing check (use `--module <module>` plus a synthetic `is_overridden` override that flips a normally-passing check to fail, or create a tiny fixture module under `tests/fixtures/`)
    3. Runs `bin/dotfiles-doctor` with PATH including the stub
    4. Asserts notify.log contains `failing:` and at least one valid check ID matching `^[a-z]+\.[a-z_]+$`
  - **Files**: `tests/doctor-notification.bats` (new), maybe `tests/fixtures/notification-fail-module/` (new) for the synthetic failing module
  - **Acceptance**: New bats file runs in `make check`, passes on green doctor (asserts no notification) AND on forced-fail fixture (asserts notification names IDs).
  - **Surfaced-by**: 2026-05-25 — populating doctor notification with failing IDs; manual verification used stubs, automated coverage is the right durable form.

- [ ] `chrome-enforce-profile` falls back to non-existent `Profile 2` when work-email detection misses
  - **ID**: chrome-enforce-profile-bad-default-fallback
  - **Tags**: chrome, regression-risk, observed-2026-05-25
  - **Details**: When `bin/chrome-enforce-profile` scans Local State for a profile whose `user_name` contains the configured work email domain and finds none, it falls back to the hardcoded literal `work_profile = "Profile 2"` (line near end of the Python heredoc). It then patches `Local State` to set `last_used = "Profile 2"`. On most Macs that profile dir does not exist — Chrome either creates an empty `Profile 2` on next cold launch or shows the profile picker, neither of which is the intended Work profile. This was the latent shape of the same bug fixed in `~/Applications/ChromeWork.app` (which had `Profile 2` baked in as the hardcoded routing target — see PR adding `bin/chromework-install`). Right fallback: `"Default"` (always exists on a Chrome-installed Mac) AND skip the patch entirely with a warning if no Work-signed profile is found, since the script's purpose is to enforce the Work profile — there's nothing to enforce if it can't be detected.
  - **Files**: `bin/chrome-enforce-profile`, `tests/chrome-enforce-profile.bats`
  - **Acceptance**: Script either (a) writes `Default` (not `Profile 2`) when detection misses, or (b) exits 2 with a logged warning. A new bats case `chrome-enforce-profile: skips patch when no work-domain profile present` locks the behaviour in. `dotfiles doctor` (after fix) on a non-enterprise / freshly-signed-out Mac no longer rewrites Local State.
  - **Surfaced-by**: 2026-05-25 implementing `bin/chromework-install` — the existing ChromeWork.app on the operator's machine had `Profile 2` baked into its AppleScript routing target, traced back to the same `chrome-enforce-profile` fallback constant.

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
       when Ollama lands MTP speculative decoding for non-Gemma models
       (track via `track-ollama-speculative-decoding-pr`).

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

- [ ] Auto-fix `opencode.json` tools:true when the doctor detects it missing
  - **ID**: doctor-opencode-tools-auto-fix
  - **Tags**: doctor, local-ai, fix-mode, opencode
  - **Details**: `modules/local-ai/doctor.sh:99-126` declares the
    `local-ai.opencode_tools_enabled` check today but only as
    verification (the file is agentbrew's per the dotfiles/agentbrew
    boundary). In practice the user-local `~/.config/opencode/opencode.json`
    is small enough — and the fix surgical enough (set
    `provider.ollama.models.<each-entry>.tools = true`) — that a
    fix-mode would save the operator the JSON-edit step. Add a tiny
    `_opencode_fix_tools_flag()` helper that runs a Python script to
    rewrite the file in place when `--fix` is on, and only on entries
    that don't already have `tools: true`. Preserve all other keys.
    Add a `tests/module-local-ai-opencode-fix.bats` to lock the
    JSON-rewrite invariants (no key dropped, idempotent, leaves
    non-Ollama providers untouched).
  - **Files**: modules/local-ai/doctor.sh, tests/module-local-ai-opencode-fix.bats
  - **Acceptance**: `dotfiles doctor --module local-ai --fix` rewrites
    the user's opencode.json adding `tools: true` to every Ollama
    model entry that lacks it; new bats locks JSON shape; idempotent
    on repeated runs.

- [ ] Wire `tests/verify-counts.bats` into the pre-commit gate
  - **ID**: ci-gate-verify-counts
  - **Tags**: ci, drift, counts
  - **Details**: Docs must not carry hand-maintained module, test, check, or
    settings counts (`make count` prints live numbers). `tests/verify-counts.bats`
    already fails when scanned docs include those patterns; it is not enforced on
    every docs-touching commit. Add a step to either `git-hooks/pre-commit` or
    `.github/workflows/ci.yml` gated on a pathspec (`README.md`, `AGENTS.md`,
    `CONTRIBUTING.md`, `docs/human-blocked-actions/`, other files listed in
    `tests/verify-counts.bats`). On failure, point editors at `make count` and
    tell them to delete volatile counts instead of updating them.
  - **Files**: git-hooks/pre-commit (or .github/workflows/ci.yml), tests/verify-counts.bats
  - **Acceptance**: `bats tests/verify-counts.bats` runs automatically on commits
    that touch the scanned doc paths; failing run blocks the commit/PR; passing
    run is silent.

- [ ] Personal-machine doctor module — verifies one-time personal machine setup
  - **ID**: personal-machine-doctor-module
  - **Tags**: doctor, personal-machine, machine, setup
  - **Details**: Discovered 2026-05-15: on a fresh boot of the personal machine, `git config --global user.email` was unset and `~/apps/dotfiles` / `~/apps/agentbrew` were not cloned — with no automated detection, no doctor check, and no recovery hint. Add `modules/personal-machine/doctor.sh` that checks: (1) `git config --global user.email` is `fyodor@sent.com` (not @company.example, not blank); (2) `~/apps/dotfiles` is a git checkout with `origin` = `github.com/fyodoriv/dotfiles` on branch `feat/chezmoi`; (3) `~/apps/agentbrew` is a git checkout with `origin` = `github.com/fyodoriv/agentbrew` on branch `main`. Each check has `?` / `✗` / `✓` states and prints the exact fix command on failure (e.g. `git config --global user.email "fyodor@sent.com"` or the clone + checkout command from `docs/personal-machine-setup.md`).
  - **Files**: `modules/personal-machine/doctor.sh` (new), `tests/personal-machine-doctor.bats` (new)
  - **Acceptance**: `dotfiles doctor --module personal-machine` passes on a correctly configured machine; fails with actionable one-liner hints on a machine missing any of the checks; `make check` green.
  - **Surfaced-by**: 2026-05-15 personal-machine setup — global git identity was unset, repos were missing, nothing detected it.

- [ ] gh-wrapper human-context tests: enforce env isolation OR put `! grep` last
  - **ID**: gh-wrapper-human-context-test-env-isolation
  - **Tags**: gh-wrapper, tests, false-positive, scout
  - **Details**: The three "human context" tests in `tests/gh-wrapper.bats` (#16 `pr close --comment leaves text unchanged`, #18 `pr comment --body leaves human-authored text unchanged`, #27 `gh api -f body= leaves human-authored text unchanged`) use `! grep -q "Written by an agent"` as a non-final assertion in the middle of the test body. Bash's `set -e` is suppressed for negated commands (POSIX `set -e` semantics), so when the negation logically fails (i.e. the wrapper DID append a footer), the test doesn't terminate — it continues to the next line and passes if that one succeeds. The operator's `~/.zshrc.ai-tools` exports `DEVIN_MODEL`, which `_gh_wrapper_is_agent_context` interprets as agent context, so the wrapper unconditionally appends the footer in every locally-run bats invocation. The tests pass on the operator's machine despite asserting the opposite of what's happening. The fix has two acceptable shapes — pick one consistently across the three tests: (a) wrap the run with `env -u AGENT_PUBLIC_WRITE_GUARD -u DEVIN_MODEL -u DEVIN_SESSION_ID -u CLAUDE_CODE_SSE_PORT -u CURSOR_AGENT -u WINDSURF_AGENT -u CODEX_AGENT "$GH_WRAPPER" …` (matches the new `gh api --input` human-context test #35 added in this PR); (b) move the `! grep` assertion to the LAST statement in the test body so its non-zero exit IS the test return code. (a) is the more rigorous fix because the human-context coverage is about what the wrapper does without agent env, not about what the assertion order is.
  - **Files**: tests/gh-wrapper.bats (tests #16, #18, #27)
  - **Acceptance**: each of the three tests fails (cleanly, with a clear bats error) when DEVIN_MODEL is set, then passes after the env-isolation fix is applied. A new bats meta-test verifies that running the wrapper with `env -u DEVIN_MODEL …` produces no footer for human input.
  - **Surfaced-by**: 2026-05-16 debug session for #gh-wrapper-api-input-json (PR #44) — new human-context test #35 failed correctly because `!` was the last assertion; tracing the discrepancy to the existing tests showed the same `!`-mid-test silent pass.

- [ ] Add ASD-STE100 + ADHD-friendly agent output rules to Agentfile.yaml
  - **ID**: agentfile-asd-ste100-adhd-output-rules
  - **Tags**: agentfile, rules, agentbrew, docs
  - **Details**: Add two always-on shared rules to the `Agentfile.yaml` `rules:` block so every agent on every machine writes in ASD-STE100 Simplified Technical English and communicates for an ADHD reader (BLUF, scannable, one next step). Exact lines to append to the end of the `rules:` block: `Write all output in ASD-STE100 Simplified Technical English: short sentences (aim for 20 words or fewer), active voice, present tense, one instruction per sentence, common approved words, no idioms, jargon, or synonyms; define a technical term once, then reuse the same term.` and `Communicate for an ADHD reader: state the answer or next action first (bottom line up front), keep paragraphs short, use bullet lists, bold the single key point, stay scannable, and end with one clear next step.` Also add two `grep -q` assertions to the "Agentfile inline rules cover delivery safety invariants" test in `tests/agent-artifact-coverage.bats` asserting these two strings are present, so they can't silently regress. Generic content, no org identifiers — belongs in the base repo.
  - **Files**: Agentfile.yaml, tests/agent-artifact-coverage.bats
  - **Acceptance**: `Agentfile.yaml`'s `rules:` block contains both new lines; `bats tests/agent-artifact-coverage.bats` exits 0 including the new assertions; `agentbrew sync --dry-run` propagates the rules block unchanged in shape (no schema break).

- [ ] Restore the `dotfiles-doctor --quiet` 90-second runtime budget
  - **ID**: doctor-quiet-runtime-budget
  - **Tags**: doctor, performance, tests, regression
  - **Details**: `tests/doctor.bats` test `doctor --quiet completes in under 90 seconds` flakes when `make check` runs tests in parallel, on both the feature checkout and the clean `dotfiles-applied` checkout. Instrument the quiet doctor path by module and command so the slow dependency is visible, then add bounded timeouts or move non-critical work out of the quiet path without weakening doctor coverage.
  - **Files**: bin/dotfiles-doctor, modules/*/doctor.sh, tests/doctor.bats
  - **Acceptance**: the focused Bats test passes on this machine and `make check` passes without excluding the doctor runtime test.
  - **Surfaced-by**: 2026-09-27 Amphetamine safety delivery; feature and clean-applied checkouts both exceeded the existing 90-second gate.

## P3

- [ ] Stop `uv tool install poetry` failing on every apply when another installer owns poetry
  - **ID**: uv-tools-skip-foreign-poetry
  - **Tags**: scout, uv, python, apply, noise
  - **Details**: `.chezmoiscripts/run_after_uv-tools.sh` runs `uv tool install` for `poetry`, `jrnl`, `httpie` and `pipx` when `uv tool list` lacks them. On 2026-09-28, `~/.local/bin/poetry` came from the official poetry installer (it links into `~/Library/Application Support/pypoetry/venv`), and `/opt/homebrew/bin/poetry` also existed. So every apply printed `error: Executable already exists: poetry` and `⚠ uv tool install poetry failed — continuing`. Fix: before installing, check whether `~/.local/bin/<tool>` exists and is not uv-managed. If so, print one `○ <tool> skipped (installed by <owner>; remove it to let uv manage it)` line and continue.
  - **Files**: .chezmoiscripts/run_after_uv-tools.sh, tests/ (the uv-tools bats file)
  - **Acceptance**: (1) a fake non-uv `~/.local/bin/poetry` produces one skip line and no failure line; (2) with no existing executable, the tool installs as before; (3) bats covers both.
  - **Hypothesis**: The warning comes only from an executable that another installer owns. Detecting it takes `uv tool install poetry failed` lines per apply from 1 to 0 without changing which poetry runs.
  - **Success**: The Measurement prints 0 on a machine where the official installer owns poetry.
  - **Pivot**: If the owner cannot be detected reliably, add a chezmoi data list of tools to skip instead of detecting ownership.
  - **Measurement**: `bash "$(chezmoi source-path)/.chezmoiscripts/run_after_uv-tools.sh" 2>&1 | grep -c "uv tool install poetry failed"`
  - **Anchor**: Nielsen, "10 Usability Heuristics for User Interface Design", 1994, heuristic 8 (aesthetic and minimalist design: a warning that repeats on every run and needs no action hides real warnings).

- [ ] Doctor flags deployed LaunchAgents from other owners that run without a locale
  - **ID**: doctor-launchagent-locale-other-owners
  - **Tags**: scout, launchagents, doctor, locale
  - **Details**: `tests/launchagents.bats` now requires `LANG=C.UTF-8` in every dotfiles plist, because launchd sets no locale and the `bin/awk` shim (Homebrew gawk) then fails unanchored regex matches. Plists from other owners are not covered: `com.minsky.*` in `~/Library/LaunchAgents/` sets only `PATH` and `HOME`. Add one advisory doctor check that lists deployed non-`com.dotfiles.*` plists without `LANG` or `LC_ALL`, and file the fix in each owning repo.
  - **Files**: modules/security/doctor.sh (next to the existing `security.deployed_la_*` checks)
  - **Acceptance**: `dotfiles doctor` warns once, naming each deployed plist without a locale; no dotfiles code writes plists it does not own.

- [ ] Deploy the watchman LaunchAgent plist or drop it from the reload list
  - **ID**: watchman-plist-deploy-or-drop
  - **Tags**: scout, launchagents, watchman, drift
  - **Details**: `bin/dotfiles-reload-launchagents` ends with `⚠ skip com.github.facebook.watchman — plist not deployed (~/Library/LaunchAgents/com.github.facebook.watchman.plist missing; run dotfiles apply first)` and advises `Deploy missing plists: dotfiles apply`. But `dotfiles apply` was run immediately before and did not create it, so the advice is a dead end and the warning is permanent — it reports `10 reloaded, 1 skipped (bootstrap)` on every single delivery. Either the plist should be deployed by apply (if watchman is a supported dependency) or `com.github.facebook.watchman` should be removed from the reload list (if it is vestigial). Decide which, then make the reload output clean.
  - **Files**: launchagents/, bin/dotfiles-reload-launchagents, .chezmoiscripts/run_after_launchagents.sh.tmpl, tests/launchagents.bats
  - **Acceptance**: (1) `bin/dotfiles-reload-launchagents` reports 0 skipped on a converged machine; (2) if watchman is dropped, no reference to it remains in the reload list; (3) if it is kept, `dotfiles apply` deploys its plist and the agent loads.

- [ ] Replace? Relocate: agent-browser singleton helpers
  - **ID**: replace-relocate-agent-browser-singleton-helpers
  - **Tags**: scout, agent-browser, reuse, upstream
  - **Details**: `bin/agent-browser-singleton-preflight`, `bin/agent-browser-reap-strays`, and the safe `~/.agent-browser/{ensure,launch}-chrome.sh` compatibility wrappers are intentionally thin host-local adapters over `agent-browser --cdp` and Chrome CDP. Revisit whether this layer should be contributed upstream to agent-browser, moved into agentbrew shared browser policy tooling, or kept in dotfiles because it depends on this repo's launchd profile/port contract.
  - **Files**: bin/agent-browser-singleton-preflight, bin/agent-browser-reap-strays, dot_agent-browser/executable_ensure-chrome.sh, dot_agent-browser/executable_launch-chrome.sh, modules/agent-browser/doctor.sh
  - **Acceptance**: Document one decision: upstream PR/filed issue, relocation to agentbrew, or "keep in dotfiles" with a current reason; if relocating, add/point to the implementation task in the owning repo.

- [ ] Ship lifecycle hook templates in `agent-hooks/` — Think → Plan → Build → Review → Test → Ship → Reflect
  - **ID**: agent-hooks-lifecycle-templates
  - **Tags**: agent-hooks, ecosystem-alignment, lifecycle, scout
  - **Details**: The 2026-05-25 ecosystem audit (see agentbrew PR #1042) surfaced that two upstream primitives have converged on the same hook lifecycle: [`right-hooks`](https://registry.npmjs.org/right-hooks) ships the `Think → Plan → Build → Review → Test → Ship → Reflect` lifecycle with mechanical gates that block the agent from skipping phases; Nick Tune's [hook-driven workflow](https://nick-tune.me/blog/2026-02-28-hook-driven-dev-workflows-with-claude-code/) implements the same idea as a DDD workflow-engine aggregate. Both are state machines that prevent transitioning from `planning` to `reviewing` without going through `developing` first.

    dotfiles' `agent-hooks/` directory currently has one hook (`block-dangerous-git.sh`) — a `PreToolUse` matcher that processes JSON on stdin and exits with code 2 to block destructive git commands. This is the right shape for individual gates but doesn't compose into a lifecycle.

    Concrete shape: add a `agent-hooks/lifecycle/` subdirectory with one hook per lifecycle phase:

    - `phase-gate-plan.sh` — `UserPromptSubmit` hook that detects "implement X" prompts before a plan file exists and blocks with "Write a plan in `.claude/plans/<task>.md` first"
    - `phase-gate-build.sh` — `PreToolUse` matcher on `Edit|Write` that blocks edits when the plan file is missing or has no `## Tasks` section
    - `phase-gate-review.sh` — `Stop` hook that detects "build complete" claims when tests haven't been run; blocks until test command produces output
    - `phase-gate-test.sh` — `PostToolUse` matcher on `Bash` that intercepts test commands and asserts they exit 0 before marking the phase complete
    - `phase-gate-ship.sh` — `Stop` hook that blocks PR creation when review hasn't been recorded (e.g. no `## Review` section in the plan file)
    - `phase-gate-reflect.sh` — `Stop` hook that prompts the agent to append a `## Reflect` section before exit when the session shipped code

    The state lives in a single `.claude/lifecycle/<task>.yaml` file with `phase: planning|developing|reviewing|testing|shipping|reflecting` and `completed: [<phase>...]`. Each phase-gate hook reads + updates this file via flock to prevent race conditions.

    Templates ship as `agent-hooks/lifecycle/*.sh.template` — users opt-in by copying to `agent-hooks/lifecycle/*.sh` and the chezmoi lifecycle script wires them into `~/.claude/settings.json` via agentbrew's hooks-sync. Default is OFF — opt-in via Agentfile flag `lifecycle_gates: true`. This matches dotfiles rule #8 (agent config flows through agentbrew).

    Cross-link: agentbrew P3 task `catalog-refs-ralph-and-right-hooks` adds catalog references to `right-hooks` upstream. If `right-hooks` covers ≥80% of what these templates do, prefer pointing at right-hooks (`npm install -g right-hooks`) and ship only the templates that fill genuine gaps (e.g. the Reflect phase that right-hooks may not enforce).
  - **Files**: `agent-hooks/lifecycle/*.sh.template` (6 templates), `agent-hooks/lifecycle/README.md` (new — explains the lifecycle + opt-in), `Agentfile.yaml` (add `lifecycle_gates` flag), `tests/agent-hooks-lifecycle.bats` (new — exercises each template against fixture stdin), `docs/agent-hooks.md` (extend with lifecycle section).
  - **Acceptance**: (a) all 6 template files exist with proper shebang + JSON-stdin processing matching `block-dangerous-git.sh` shape; (b) opt-in flag in `Agentfile.yaml` toggles deployment; (c) `tests/agent-hooks-lifecycle.bats` exercises each template against synthetic Claude Code stdin payloads and verifies the right exit code; (d) `docs/agent-hooks.md` documents the lifecycle, the opt-in flow, and the cross-link to upstream `right-hooks`; (e) `make check` green.
  - **Surfaced-by**: 2026-05-25 ecosystem audit (agentbrew PR #1042 — research synthesis of HN trends + Anthropic plugin marketplace + Minsky pattern adoption).

- [ ] Document Lean Terminal as the recommended Obsidian terminal plugin for Claude Code
  - **ID**: obsidian-lean-terminal-recommendation
  - **Tags**: obsidian, tooling, documentation, claude-code, dx
  - **Details**: After comparing all active Obsidian terminal plugins (polyipseity/obsidian-terminal 809★, sdkasper/lean-obsidian-terminal 90★, ZyphrZero/Termy 37★), Lean Terminal is the right pick for launching Claude Code from inside Obsidian. Reasons: (1) built with Claude Code in mind — startup command config, session registry scanning `~/.claude/projects/`, `Shift+Enter` muscle-memory support; (2) avoids two open polyipseity bugs that specifically break Claude Code: scroll-to-top during streaming on macOS (polyipseity#70), and Windows PTY resizer accidentally invoking `claude.exe --print` on startup (polyipseity#142); (3) full PTY via node-pty, not a command runner — Claude Code's interactive UI works correctly.

    Concrete shape: add a `docs/obsidian.md` (or a section in `docs/tooling.md` if that exists) documenting: which plugin, why, install steps (community plugin store → "lean-terminal"), and the recommended startup command setting (`claude` or `claude --project .`). This is a doc-only task — the install itself is already done on the operator's machine (travel vault, v1.1.1, arm64 binary, 2026-05-18).
  - **Files**: `docs/obsidian.md` (new) or `docs/tooling.md` (extend if exists)
  - **Acceptance**: A new or updated doc explains the plugin choice with rationale; a teammate reading it could reproduce the install from scratch without context from this session.

- [ ] Apply the same DOTFILES_DIR resolver to `run_once_bootstrap.sh`
  - **ID**: chezmoiscripts-dotfiles-dir-resolver-bootstrap
  - **Tags**: chezmoi, scripts, robustness, scout
  - **Details**: Surfaced while fixing the agentbrew sync script in PR #42. `run_once_bootstrap.sh` uses the same brittle `DOTFILES_DIR="$(cd "$(dirname "$0")/.." && pwd 2>/dev/null || echo "$HOME/apps/dotfiles")"` pattern that silently resolves to a `/var/folders/.../` tmpdir when chezmoi copies the script to its run cache. The `||` fallback never triggers because `cd` to the tmpdir's parent succeeds. The bootstrap script then references `$DOTFILES_DIR/gitconfig.local.example` — when the path is a tmpdir, the file is missing, so the gitconfig.local block silently skips. Apply the same `_resolve_dotfiles_dir` shape used in `.chezmoiscripts/run_after_agentbrew-sync.sh` (probe `$(dirname $0)/..` → `chezmoi source-path` → known layouts) — or, better, extract the resolver to `lib/dotfiles-dir.sh` and source from both scripts. Same pattern also lives in `.chezmoiscripts/run_onchange_after_amphetamine-prefs.sh.tmpl`; either fix in this PR or file as a separate sibling task.
  - **Files**: `.chezmoiscripts/run_once_bootstrap.sh`, `.chezmoiscripts/run_onchange_after_amphetamine-prefs.sh.tmpl`, `lib/dotfiles-dir.sh` (new, optional), `tests/chezmoiscripts.bats`
  - **Acceptance**: running each script under chezmoi tmpdir execution (covered by a new bats case that copies the script to a tmpdir + mocks `chezmoi source-path`) resolves to the dotfiles repo and exercises its intended side effects; `make check` green.
  - **Surfaced-by**: 2026-05-16 debug session for PR #42 — `bash -x .chezmoiscripts/run_after_agentbrew-sync.sh` revealed the `dirname $0/..` trap; the same pattern is in 2 sibling scripts.

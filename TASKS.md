# Tasks


<!-- policy: do NOT bypass commit hooks (--no-verify) and do NOT push to a
remote without explicit operator approval in the current session. -->

<!-- policy: every new task names the competitive scorecard metric it
advances (a **Competitive-goal** line). The metrics are in
docs/competition/scorecard.md; run scripts/benchmark-run.sh --json to refresh
them. -->

## P0

## P1

- [ ] Verify guard decisions against later hook rewrites
  - **ID**: guard-final-command-hook-order
  - **Tags**: hooks, security, reliability
  - **Details**: The Agentfile registers the heavy-run guard and a path hook for Bash. The path hook can return updated command input. The public hook contract documents updated input, but the effect of hook ordering on the final executed command has not been established for the configured agents. This is a verification gap, not a demonstrated bypass. Use only synthetic commands, a scratch agent configuration and canaries; never run a destructive command. The hooks emit different response formats for Claude and Codex; qualify each host and version separately.
  - **Files**: `Agentfile.yaml`, `agent-hooks/require-heavy-run.sh`, `agent-hooks/prepend-endpoint-path.sh`, their tests and hook guidance as needed.
  - **Output**: code
  - **Acceptance**: A qualified scratch invocation records each guard input and proves the final command was delivered to a harmless canary executor, including benign path rewrites and synthetic attempted rewrites. A guard decision cannot be used as proof for an unguarded final command. Untested hosts and missing ordering evidence remain unqualified.
  - **Hypothesis**: A qualified ordering contract or enforcement change yields zero unguarded final synthetic commands across a preregistered positive and negative matrix, without losing existing safe allowances or treating benign path rewrites as failures.
  - **Measurement**: First commit exact cases, each host and version, non-destructive canaries and a safe scratch invocation command. Record each guard input and final executor input, run the existing hook suites and the new focused matrix, then run the repository gate.
  - **Success**: All registered cases are observed exactly once; unsafe synthetic rewrites yield zero unguarded final commands; benign path rewrites retain their behavior; all required tests and the gate pass.
  - **Pivot**: Any unobserved final command, unsafe unguarded rewrite, false safety claim, unexpected execution or failed gate rejects the candidate; retain evidence and redesign.
  - **Anchor**: Agentfile hook declarations; Claude Code hook reference at https://code.claude.com/docs/en/hooks; Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — correctness of existing command guards, not a scorecard metric.

- [ ] Keep selected machine connector credentials fresh without leaks
  - **ID**: github-connector-machine-credentials
  - **Tags**: security, git, machine, rust, preparation
  - **Details**: User assigns the GitHub header helper and stale GUI credential doctor to dotfiles; request is agentbrew issue #693. Register C01–C14, then land runnable Rust instrumentation before native wiring. Clear both token variables only for the keyring-backed callback. Preserve ordinary gh and explicit-token users. Plan: [machine credential controls](docs/plans/github-connector-machine-credentials.md).
  - **Files**: `tests/fixtures/connector-credentials/`, `docs/plans/github-connector-machine-credentials.md`; future native adapter and existing doctor check/fix/recheck boundary.
  - **Output**: instrumentation
  - **Acceptance**: Exact absent/matching/stale/unknown decisions; selected repair handles stale nonempty GUI values and verifies the result. Unknown/unconfigured policy performs no lookup/write. No secret values or digests in diagnostics. Native callback/coverage stays unavailable until source qualification.
  - **Hypothesis**: A callback-scoped keyring boundary and typed repair state make every sealed pure decision correct with zero wrong token selections, unauthorized mutation proposals, false fixed results or synthetic-marker disclosures.
  - **Measurement**: `heavy-run cargo test --offline --locked --manifest-path tests/fixtures/connector-credentials/Cargo.toml --test connector_credentials_contracts -- --test-threads=1`, then `heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`. The fixture target qualifies preparation; native activation requires its own registered measurements.
  - **Success**: All pure assertions and positive controls pass; unsafe proposals, false fixed results and diagnostic marker disclosures are zero. Qualify native behavior separately before activation.
  - **Pivot**: Any unrelated-token override, unknown-as-absent decision, unsafe mutation, false repair or secret disclosure rejects the boundary; preserve the oracle and redesign the adapter.
  - **Anchor**: agentbrew issue #693 and user ownership clarification; Basili/Caldiera/Rombach 1994 GQM; Munafò et al. 2017 pre-registration; OWASP Logging Cheat Sheet.
  - **Competitive-goal**: none — machine credential correctness and privacy, not a scorecard count.
  - **Evidence**: Original prediction `7d6006d`; transfer prediction `05cc929`. The standalone fixture retains the sealed corpus and passes its focused gate. Native work needs an owned installed callback, the qualified shared bounded worker and a secret-safe GUI writer or covered removal policy. See the plan.


- [ ] Prepare private evidence for compiler runs outside queue ownership
  - **ID**: compiler-queue-observation
  - **Tags**: stability, privacy, instrumentation, agents
  - **Details**: The current doctor observer recognizes headless Chrome ancestry only. Prepare a source-bound compiler observation contract and independent synthetic oracle before adding any observer. Process names, nice levels, working folders and an inherited lease marker do not prove reservation ownership. Keep unsupported or stale evidence explicitly unknown. This is separate from the immediate classifier fix and the future Rust queue port. A pre-measurement source review found that the synthetic observation does not identify its defined root and must reject conflicting PID generations; register and review that evidence contract before a new decision candidate. No candidate or holdout decision result was measured. See [decision model](docs/plans/compiler-queue-decision-model.md). Scope and registration prerequisites: [Queue caller coverage](docs/plans/queue-caller-coverage.md#rollout-security-and-regression-coverage).
  - **Files**: proposed observer contract and synthetic fixtures; existing `bin/headless-chrome-unlocked` and `tests/headless-chrome-unlocked.bats` are references, not compiler acceptance tests.
  - **Output**: instrumentation
  - **Acceptance**: commit a reviewed evidence protocol, fixed safe output and independent synthetic decision matrix before observer code; prove zero false-owned verdicts and no private payload disclosure. Real ownership is asserted only from verified reservation identity, never a process-name or priority heuristic. No automatic process actions or setting changes.
  - **Hypothesis**: a verified identity boundary yields zero false-owned and zero false-safe unknown verdicts across its preregistered synthetic controls, while known-valid controls pass; the existing browser-only harness cannot establish that result.
  - **Measurement**: preparation first — commit the exact observer protocol, frozen inputs and runnable synthetic command before code or results. The proposed `heavy-run env JOBS=1 bats ./tests/compiler-queue-observer.bats` is not implemented or accepted at task creation. Preserve browser fixture results separately; do not use a live snapshot as a preregistered baseline.
  - **Success**: 100% expected decisions in the later sealed oracle, zero false ownership/safe-unknown verdicts or disclosures; missing instrumentation stays non-green.
  - **Pivot**: any false-owned verdict, stale identity accepted as current, unverified input marked safe or private diagnostic rejects the observer design. Change the evidence protocol rather than reducing the claim to a process-name match.
  - **Anchor**: Basili, Caldiera, Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration; current heavy-run controller identity and held-marker contracts.
  - **Competitive-goal**: none — private queue coverage evidence, not a scorecard count.


- [ ] Keep heavy-run metadata private without changing safe parallel admission
  - **ID**: heavy-run-private-metadata
  - **Tags**: stability, security, privacy, agents
  - **Details**: The prediction in ad87838 registers seven synthetic disclosure cases. The preserved baseline disclosed its marker in all seven. Phase A reader preparation is an AFK engineering dependency, not completion: it still writes raw project fields. Complete the reader adapter first, then prepare a bounded cutover guard for strict 429 and 430 leaders, owners, pending grants, waiters and pre-ticket launchers. Only a verified supported-entrypoint replacement may enable opaque writers. Missing or unknown reader evidence refuses activation. Let unowned old work drain; restart only owned queued work. Do not rewrite live records, copy private data, change owner slot limits, or treat one empty-queue snapshot as proof. Keep this task open after Phase A.
  - **Files**: `bin/heavy-run`, `tests/heavy-run-privacy.bats`, `tests/heavy-run-project-identity.bats`, `tests/helpers/`, `docs/plans/queue-project-reader-preparation.md`, `docs/plans/heavy-run-private-metadata.md`, `docs/agent-hooks.md`; the bounded native cutover instrument and launch-before-load bootstrap are proposed and must be registered and verified before opaque writers.
  - **Output**: code
  - **Acceptance**: new ticket, owner, wait and status records omit raw command arguments, working folders and project names in every frozen disclosure case; all raw/typed project-cap, FIFO, exclusive, priority, exit-status, orphan, memory and realtime contracts pass. Activation stays refused while any supported strict old reader can decide. Legacy live records remain owned by their controllers. Phase A alone does not meet this acceptance.
  - **Hypothesis**: opaque job/project identity and bounded wait categories reduce synthetic-marker disclosures from seven of seven cases to zero of seven, while wrong admissions and scheduling regressions remain zero. Reader-first preparation prevents mixed-version project undercounting before opaque writers activate.
  - **Measurement**: preserve the seven original fixtures byte-for-byte (Git blob `2f6036c88c979bc5aa5f2fe0bf3fe4f766710c7c`), then run `heavy-run env JOBS=1 bats ./tests/heavy-run-privacy.bats` plus the original ten and four duplicate-field controls, current scheduling suite, and `heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`. First implement and register the bounded cohort/atomic-entrypoint instrument; its missing, busy, partial-record, pre-ticket-old and interrupted-cutover controls must all refuse activation before an opaque-writer result is accepted. These future fixture/instrument paths are not installed commands at this task's registration.
  - **Success**: zero disclosures in all seven frozen cases, zero wrong admissions or lost scheduling contracts, every negative cutover control refuses safely, and every required gate exits zero. Honor configured total/project slots and memory policy throughout.
  - **Pivot**: any disclosure, wrong admission, unverified activation, old-file mutation or changed scheduling contract rejects the metadata boundary. Keep raw-writer preparation active and redesign the failing boundary; never bypass the guard or weaken a fixture.
  - **Anchor**: OWASP Logging Cheat Sheet, Data to exclude; Basili, Caldiera, Rombach (1994), Goal Question Metric; original ad87838 prediction and the current project-cap protocol.
  - **Competitive-goal**: none — queue metadata privacy and safe machine capacity, not a scorecard count.

- [ ] Headless browser test runs bypass the heavy-run lock
  - **ID**: headless-browser-runs-bypass-heavy-run
  - **Blocked**: needs-time — 2026-10-28: shipped the hook extension (e2e/ui scripts, exec playwright, make e2e/test-all) and the doctor check `resilience.headless_chrome_under_heavy_run`; Acceptance part 1 is met. Part 2 needs data: read the unexplained-overload count in the tooling-checkup machine-metrics phase on the next two checkups after this lands, then close (under 40 rows, peak load1 under 100) or pivot (over 150 rows).
  - **Tags**: performance, reliability, agents
  - **Details**: The 2026-10-27 `/tooling-checkup` found 197 unexplained overload rows (load1 over 20) in the last 24 h of `machine_metrics`, peak load1 257.6 at 2026-10-27T09:16. The top processes in those rows were `chrome-headless-shell` (112 rows), `python` (105), and `node` (84). The 2026-10-25 checkup had the same 197 count, so the problem persists. `heavy-run` only queues commands that agents wrap by hand; Playwright and agent-browser runs started directly (e2e suites, UI audits, MCP browser sessions) do not take the lock. Find which callers start headless Chrome without the lock, then make the lock hard to skip: for example, a Playwright/agent-browser wrapper on PATH that takes the `heavy-run` lock, or a doctor/hook warning when a browser test runs outside it.
  - **Files**: `bin/heavy-run`, `modules/resilience/doctor.sh`, `docs/` (heavy-run doc), `tests/`
  - **Output**: code
  - **Acceptance**: a headless browser test run started without `heavy-run` either queues on the lock or is reported by the doctor; the next two checkups show the unexplained overload count under the Success threshold.
  - **Hypothesis**: routing headless browser test runs through the `heavy-run` lock cuts unexplained overload rows (load1 over 20) in 24 h of `machine_metrics` from 197 to under 40, because parallel `chrome-headless-shell` fan-out is the top process in those rows.
  - **Measurement**: the unexplained-overload count in the tooling-checkup machine-metrics phase (24 h window of `machine_metrics`, rows with load1 over 20 and no `heavy-run` holder), on the next two checkups after the change lands.
  - **Success**: under 40 rows per 24 h and peak load1 under 100 on both checkups.
  - **Pivot**: over 150 rows on both checkups -> the lock is not the lever; profile the `python` and `node` rows instead and drop the wrapper approach.
  - **Anchor**: tooling-checkup runs 2026-10-25 and 2026-10-27 (machine_metrics phase); Gunther 2007, *Guerrilla Capacity Planning* (load beyond core count); Forsgren, Humble, Kim 2018 (stability).
  - **Competitive-goal**: none — machine stability for agent work (docs/metrics.md), not a scorecard metric.

## P2

- [ ] Decide whether pull requests must carry a Vision trace block
  - **ID**: decide-pr-vision-trace-gate
  - **Tags**: ci, docs, process
  - **Details**: `.github/workflows/pr-vision-trace.yml` failed every pull request that had no `Vision trace` block. No recent pull request body has one, so the workflow is parked: it starts only by hand. The owner decides: restore the `pull_request` trigger and add the block to the PR template and agent rules, or delete the workflow and its script.
  - **Files**: `.github/workflows/pr-vision-trace.yml`, `docs/ship-it-reference.md`.
  - **Output**: decision, then code
  - **Acceptance**: the workflow either runs on every pull request and passes on a body written from the template, or it is gone with its script.
  - **Hypothesis**: one clear rule moves the share of merged pull requests that match the declared trace policy from 0 of the last 6 to 6 of the next 6.
  - **Measurement**: `gh pr list --state merged -L 6 --json body --jq '[.[]|.body|test("Vision trace")]|map(select(.))|length'`
  - **Success**: 6 of 6 when the gate is kept; the workflow file is absent when it is dropped.
  - **Pivot**: fewer than 5 of 6 after the gate is restored means agents do not load the rule; drop the gate.
  - **Anchor**: Forsgren, Humble and Kim (2018), Accelerate; Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — a process decision, not a scorecard metric.

- [ ] Pin the Bats version in the hosted coverage job
  - **ID**: ci-coverage-pin-bats-core
  - **Tags**: ci, security, supply-chain
  - **Details**: The `coverage` job in `.github/workflows/ci.yml` runs `git clone --depth 1` of the `bats-core` default branch and installs it with `sudo`. Every other dependency of the workflows is pinned to a commit SHA, and `tests/github-workflows.bats` enforces that only for `uses:` lines. A changed upstream branch would run unreviewed code on the runner. The job holds a read-only token and no secret, so the risk is a broken or misleading coverage run, not a leak. Check out one release commit instead, and extend the Bats test to reject an unpinned `git clone` in a workflow.
  - **Files**: `.github/workflows/ci.yml`, `tests/github-workflows.bats`.
  - **Output**: code
  - **Acceptance**: the coverage job installs Bats at one named commit SHA, and the workflow test fails when a workflow clones a repository without a pinned commit.
  - **Hypothesis**: pinning moves unpinned third-party code fetched by the workflows from 1 source to 0.
  - **Measurement**: `bats tests/github-workflows.bats`, with a new test that counts `git clone` lines without a following `git checkout <40-hex>`.
  - **Success**: 0 unpinned sources, and the new test is red on the unchanged workflow.
  - **Pivot**: if a pinned Bats cannot run the coverage suite, drop the clone and use the runner's packaged Bats instead.
  - **Anchor**: OpenSSF Scorecard "Pinned-Dependencies" check; Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — supply-chain hygiene, not a scorecard metric.

- [ ] Make the hosted doctor and audit jobs pass on a clean runner
  - **ID**: hosted-doctor-audit-clean-runner
  - **Tags**: ci, doctor, reliability
  - **Details**: On 2026-11-10 the first hosted run of `.github/workflows/ci.yml` failed the `audit` job: `bin/dotfiles-audit` reported 47 failed checks, because it checks an installed machine (shims in `dotfiles/bin`, LaunchAgents, `~/.ssh` rights) and the runner has none. The `doctor` job runs `chezmoi apply --source "$PWD" --force` with no chezmoi config, and `chezmoi managed` fails there with `map has no entry for key "profile"`. Both jobs now start only by hand. Give the runner a config first (`chezmoi init` with fixed answers, or a CI data file), then make the audit skip machine-state checks under `DOTFILES_CI=1` the way the doctor does. The test `dotfiles managed lists files` in `tests/cli.bats` skips without a chezmoi config; remove the skip when the runner has one.
  - **Files**: `.github/workflows/ci.yml`, `bin/dotfiles-audit`, `tests/cli.bats`, `docs/ci-setup.md`.
  - **Output**: code
  - **Acceptance**: the `doctor` and `audit` jobs pass on a hosted runner and run on every push to `feat/chezmoi`; the `managed` test runs on the hosted runner without a skip.
  - **Hypothesis**: a runner with a chezmoi config and CI-aware audit checks moves hosted `doctor` and `audit` failures from 47 audit failures and 1 skipped job to 0.
  - **Measurement**: `gh workflow run ci.yml --ref <branch>` then `gh run view <id> --json jobs --jq '.jobs[] | select(.name=="doctor" or .name=="audit") | .conclusion'`.
  - **Success**: both jobs print `success` on two runs in a row.
  - **Pivot**: if `chezmoi apply` cannot finish on a runner within 30 minutes, keep `doctor` manual and gate only `audit`.
  - **Anchor**: Forsgren, Humble and Kim (2018), Accelerate (change failure rate); Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — CI coverage, not a scorecard metric.

- [ ] Make the perf gate and its tests steady on hosted runners
  - **ID**: perf-gate-hosted-runner-noise
  - **Tags**: ci, perf, reliability
  - **Details**: On 2026-11-10 `tests/perf-gate.bats` failed in 3 of 3 hosted macOS runs, each time on other tests (33; 18; 10, 17 and 20). The fixtures compare a 100 ms sleep with a 50 or 200 ms one. On the runner a 100 ms sleep took 174 to 241 ms, also when the file ran with no peer file (that change was reverted). The hosted gate now skips the file (`TEST_SKIP_FILE=tests/perf-gate.bats make check` in `.github/workflows/ci.yml`). Two parts: (1) make the fixtures independent of the wall clock (a fake timer for the verdict tests, or far wider gaps), then remove the skip; (2) check the real `make perf-gate` step on the runner: with this noise a pull request that touches a runtime path can fail with no real slowdown. Measure it with `gh workflow run ci.yml` on a branch that touches `bin/`, and decide whether the hosted run checks ceilings only.
  - **Files**: `tests/perf-gate.bats`, `scripts/perf-gate.pl`, `.github/workflows/ci.yml`, `Makefile`, `docs/ci-setup.md`.
  - **Output**: code
  - **Acceptance**: `.github/workflows/ci.yml` has no `TEST_SKIP_FILE`, and `tests/perf-gate.bats` passes every hosted run for a week.
  - **Hypothesis**: fixtures that do not depend on the wall clock move hosted failures of `tests/perf-gate.bats` from 3 of 3 runs to 0 of 10.
  - **Measurement**: `gh run list -w ci.yml -L 10 --json databaseId --jq '.[].databaseId' | xargs -I{} gh run view {} --log-failed | grep -c 'perf-gate.bats'`
  - **Success**: 0 failures of this file in 10 runs.
  - **Pivot**: if a fake timer needs a large change in `scripts/perf-gate.pl` (more than a screen of code), keep the file local-only and state that in `docs/ci-setup.md` as the final design.
  - **Anchor**: Luo et al. (2014), An Empirical Analysis of Flaky Tests; Forsgren, Humble and Kim (2018), Accelerate (change failure rate).
  - **Competitive-goal**: none — CI reliability, not a scorecard metric.

- [ ] Make the hosted coverage job finish, then put it back on every pull request
  - **ID**: hosted-coverage-job-time
  - **Tags**: ci, coverage, reliability
  - **Details**: On 2026-11-10 the `coverage` job of `.github/workflows/ci.yml` (Ubuntu, `./bin/dotfiles-coverage run tests/`: the full Bats suite under `set -x` tracing) was still running after 45 minutes in one hosted run and after 30 minutes in the next, with a 60 minute limit. It now runs only on a manual start. First measure: start it by hand and read where the time goes and which tests fail on Linux (the suite assumes macOS paths such as `/opt/homebrew`). Then choose: run it on macOS, trace only the affected test files on a pull request, or split the suite across jobs.
  - **Files**: `.github/workflows/ci.yml`, `bin/dotfiles-coverage`, `docs/ci-setup.md`, `tests/coverage.bats`.
  - **Output**: code
  - **Acceptance**: the `coverage` job passes on two pull requests in a row in under 20 minutes, and the `if:` line that limits it to manual runs is gone.
  - **Hypothesis**: tracing only what a pull request affects, on the operating system the suite targets, moves the hosted coverage job from no result in 45 minutes to a pass in under 20 minutes.
  - **Measurement**: `gh run view <id> --json jobs --jq '.jobs[] | select(.name=="coverage") | [.conclusion, .startedAt, .completedAt]'` on two pull requests.
  - **Success**: `success` twice, each under 20 minutes.
  - **Pivot**: if no layout finishes under 20 minutes, keep coverage as a weekly scheduled run and check the floor there.
  - **Anchor**: Forsgren, Humble and Kim (2018), Accelerate (change failure rate); Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — CI coverage, not a scorecard metric.

- [ ] Restore the full Bats suite with the installed CLI argument parser
  - **ID**: full-suite-bats-argument-compatibility
  - **Tags**: tests, reliability, tooling
  - **Details**: On 2026-11-08, both the unchanged base and the readiness-retro branch failed `heavy-run make test-all` before test execution with `Error: Bad command line option '--'` (exit 2). The required `make check` gate passed on the branch. Inventory every Bats `--` separator and installed-version contract; preserve safe path handling and affected-test selection. This is distinct from the one-job parallel-flag task.
  - **Files**: `Makefile`, `tests/makefile-bats-jobs.bats`, contributor test guidance.
  - **Output**: code
  - **Acceptance**: the installed Bats version accepts every full-suite invocation, all selected tests run, and paths or fixtures requiring an option separator retain a safe supported form. The same correction covers cached, serial, parallel, plugin, and e2e callers selected by the Makefile.
  - **Hypothesis**: replacing unsupported Bats argument separators with the installed CLI's supported invocation reduces argument-parser failures from 2 observed full-suite attempts to 0 without dropping selected tests.
  - **Measurement**: add a failing argument-parser reproduction to `tests/makefile-bats-jobs.bats`, run it red on the unchanged base, then run `heavy-run make test-all` after the fix and compare selected test counts.
  - **Success**: the new reproduction passes after the fix and `heavy-run make test-all` exits 0 with every selected test executed.
  - **Pivot**: if the installed Bats release lacks a safe compatible form, abandon separator removal and use a reviewed version-pinned runner or upgrade path instead.
  - **Anchor**: installed Bats help output from 2026-11-08; Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — restores the existing full-test gate, not a scorecard metric.

- [ ] Make one-job test runs work with GNU parallel installed
  - **ID**: make-check-one-job-bats
  - **Tags**: tests, reliability, tooling
  - **Details**: On Nov 7, `JOBS=1 heavy-run make check` failed before running Bats tests because Bats rejects `--no-parallelize-within-files` with `--jobs 1`. The Makefile currently supplies both whenever GNU parallel is available. Select the serial route for one job, and preserve the existing parallel route for more than one job. Do not weaken test selection or doctor isolation.
  - **Files**: `Makefile`, `tests/makefile-bats-jobs.bats`, contributor test guidance.
  - **Output**: code
  - **Acceptance**: With GNU parallel available, one-job `test`, `test-all`, and `test-force` run serially without the rejected Bats flags. Multiple-job runs retain their current parallel options. The affected-test and doctor ordering contracts remain intact.
  - **Hypothesis**: Selecting a serial Bats invocation at one job reduces rejected one-job recipes from a predicted 3/3 to 0/3, while preserving 3/3 multiple-job controls and all selected test results.
  - **Measurement**: Add named reproduction and controls to `tests/makefile-bats-jobs.bats`; run `JOBS=1 heavy-run bats tests/makefile-bats-jobs.bats` and `env -u BATS_JOBS -u TEST_FILE_JOBS JOBS=1 CACHED_RUN_DIR="$cache" heavy-run make check` with GNU parallel available and a fresh private `cache`. Record the red reproduction before the fix and preserve the parallel and doctor-order tests.
  - **Success**: All three one-job targets run without the rejected flags, all three multiple-job controls retain parallel options, and the fresh full repository gate passes without suppressing selected tests.
  - **Pivot**: Any rejected one-job recipe, lost multiple-job option, changed selected-test or doctor-order behavior, or gate failure rejects this approach; preserve the evidence and redesign the selection.
  - **Anchor**: Bats parallel execution documentation, https://bats-core.readthedocs.io/en/stable/usage.html#parallel-execution; Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.
  - **Competitive-goal**: none — reliability of the existing test gate, not a scorecard count.


- [ ] Prove agent continuity through a battery lid close with Power Protect
  - **ID**: keepawake-power-protect-physical-validation
  - **Blocked**: physical-validation — needs a person on the test laptop to complete any missing Power Protect installation with administrator authentication, disconnect power, and close the lid for a controlled comparison while actual agent progress is recorded. Check readiness first; do not ask to repeat an installation that is already present.
  - **Tags**: reliability, agents
  - **Details**: The report in #400 describes battery Clamshell Sleep with an active Amphetamine session. An AC DarkWake entry did not capture application continuity. The upstream guide describes Power Protect for power-source transitions; its two file markers establish readiness, not uptime. The read-only marker advisory is separate instrumentation. This task is only the physical experiment and the resulting coverage decision.
  - **Files**: private run evidence, `docs/troubleshooting.md`
  - **Output**: decision
  - **Acceptance**: a controlled two-minute battery lid-close comparison records both power-log sleep events and actual agent progress before and after Power Protect installation. Update the public coverage claim from the result; keep raw machine logs private.
  - **Hypothesis**: after Power Protect is installed, battery Clamshell Sleep events drop from at least one to zero during the two-minute window and the actual agent keeps making progress.
  - **Measurement**: `pmset -g log > "${LID_TEST_LOG:?}" && awk -v start="${LID_TEST_START:?}" -v end="${LID_TEST_END:?}" 'substr($0,1,19) >= start && substr($0,1,19) <= end && /Clamshell Sleep/ && /Using Batt/ {n++} END {print n+0}' "$LID_TEST_LOG"`; mandatory start/end use the power log's local `YYYY-MM-DD HH:MM:SS` format and the log path stays private. Compare the count with the actual agent's progress record for the same window.
  - **Success**: zero battery Clamshell Sleep events and continued agent progress in the post-install window.
  - **Pivot**: sleep or stalled agent progress remains -> abandon Power Protect as the sole remedy and diagnose the power/session transition; do not claim battery coverage or change system sleep policy without separate evidence.
  - **Anchor**: [Amphetamine Power Protect install guide](https://github.com/x74353/Amphetamine-Power-Protect); [App Store release notes 5.3.1/5.3.2](https://apps.apple.com/us/app/amphetamine/id937984704).
  - **Competitive-goal**: none — physical agent continuity, not a scorecard metric.

- [ ] Validate the Slack draft helper in a throwaway workspace
  - **ID**: slack-draft-live-compatibility
  - **Blocked**: needs-authorized-test-workspace — no throwaway Slack workspace or real draft-delete action is authorized for this goal. Issue #399 remains open. Synthetic tests cover only the CLI handler and generated page scripts.
  - **Tags**: browser, reliability
  - **Details**: With separate permission, use a dedicated throwaway workspace and fabricated drafts only. Check that a channel tab navigates to Drafts, count returns the exact recipient/body matches, and a fresh delete dialog confirms only the selected fabricated draft. Keep organization payloads, tokens, screenshots, and workspace URLs out of the public repo. Do not reuse a signed-in organization workspace. Before a live mutation, add a runnable compatibility harness and commit its prediction; `bats tests/slack-draft.bats` is the local safety control, not live compatibility proof.
  - **Files**: `bin/slack-draft`, `tests/slack-draft.bats`, `docs/agent-browser-policy.md`
  - **Output**: evidence
  - **Acceptance**: the authorized live harness passes all navigation, count, and scoped-confirm cases with zero wrong-row or wrong-dialog actions; issue #399 closes only after this evidence exists.
  - **Hypothesis**: the tested selectors handle all three fabricated live cases with zero unsafe actions; synthetic DOM results alone cannot establish this.
  - **Measurement**: preparation first — commit a runnable throwaway-workspace compatibility harness and its exact invocation before any live result is observed. Run `bats tests/slack-draft.bats` as the separate local safety control.
  - **Success**: three of three live cases pass and zero unsafe actions occur.
  - **Pivot**: any live mismatch or unsafe action abandons the selector contract until a safe replacement is measured.
  - **Anchor**: Basili, Caldiera, Rombach (1994), GQM; Forsgren, Humble, Kim (2018), stability.
  - **Competitive-goal**: none — browser automation stability (docs/metrics.md).

- [ ] Let a 1-file rerun pass a full-gate backlog in heavy-run (light lane)
  - **ID**: heavy-run-light-lane
  - **Blocked**: needs-owner — 2026-11-01: parked after Mac freezes. Unblock only when the owner says yes, after 24 h with no new freeze (no `force_off` in `/Library/Logs/DiagnosticReports/ResetCounter-*`, and `~/.local/state/dotfiles/heavy-run-waits.log` looks normal).
  - **Tags**: performance, agents
  - **Details**: A 1-file rerun waits behind every full gate in the one-slot queue. Draft code is on branch `park/heavy-run-light-lane` (untested; it predates #425 and must be merged with it). Design: `--light` takes one separate lane slot (`$dir/light/1`), never a heavy slot, so a light run never lets a second heavy run start. Light and heavy runs keep arrival order each in their own line. A light run waits for the ramp and normal memory pressure while a heavy run is active, never moves the ramp, and never starts while an exclusive run is queued. The draft's `--weight` option is out: at one slot it does nothing.
  - **Files**: `bin/heavy-run`, `tests/heavy-run.bats`, `scripts/heavy-run-bench.sh`, `README.md`, `Agentfile.yaml`
  - **Output**: code
  - **Acceptance**: the bench shows the rerun median wait drop and the gate wait guard holds; no new freeze in the 24 h after it lands.
  - **Hypothesis**: with `--light`, the median wait of 1-file reruns under a full-gate backlog drops 50 % or more, while the gate median wait rises at most 10 %, because a short run no longer waits behind long ones.
  - **Measurement**: `scripts/heavy-run-bench.sh` extended with a lanes mode (1 slot, a backlog of full gates plus 1-file reruns, with and without `--light`).
  - **Success**: rerun median wait down 50 % or more, gate median wait up 10 % or less, no freeze.
  - **Pivot**: rerun drop under 25 %, gate wait up over 25 %, or any freeze -> drop the lane.
  - **Anchor**: EASY backfilling (Lifka 1995; Mu'alem & Feitelson 2001); Harchol-Balter 2013, *Performance Modeling and Design of Computer Systems* (size-based scheduling).
  - **Competitive-goal**: none — machine stability and agent wait time (docs/metrics.md), not a scorecard metric.

- [ ] Record each real install run so the README can prove one-command setup
  - **ID**: proof-install-field-outcome
  - **Tags**: metrics, proof
  - **Details**: The README Proof row "One command sets up a Mac" says `not measured yet`. `bin/dotfiles-install run` writes no stats event, so no real install is counted. Add a content-free `log_run install` event with ok/error, minutes to a clean doctor, and the failing-check count, then a `scripts/proof.sh` row that reads it.
  - **Files**: `bin/dotfiles-install`, `lib/stats.sh`, `scripts/proof.sh`, `tests/proof.bats`
  - **Output**: code
  - **Acceptance**: after one real install, `scripts/proof.sh` fills the row with `real use` and the README test passes.
  - **Competitive-goal**: `manual_bootstrap_steps` (docs/competition/scorecard.md).
  - **Blocked**: needs-time — 2026-10-27: shipped the recording part. `bin/dotfiles-install run` writes one `install` stats line (ok, `duration_ms`, the heal doctor's `fail` count) and `scripts/proof.sh` fills the row from `install_clean_minutes`. No real install has run since. Unblock: after the next real install on any Mac, run `scripts/proof.sh` there and check the row says `real use`; then close.

- [ ] Skip unchanged chezmoi scripts inside a full apply
  - **ID**: apply-skip-unchanged-scripts
  - **Tags**: performance
  - **Details**: One managed-Mac checkup measured `dotfiles apply` at 537 s (#338). `--if-changed` skips a whole apply when nothing changed, and the apply now prints per-step timing (pull, chezmoi apply, doctor). Next, find which `run_after_*` scripts and doctor checks take the time, and key the slow ones on a content hash, like the JetBrains stamp.
  - **Files**: `bin/dotfiles`, `.chezmoiscripts/`, `bin/dotfiles-doctor`
  - **Output**: code
  - **Acceptance**: a second full apply with no source change spends under 60 s in `chezmoi apply`, per the timing line.
  - **Competitive-goal**: `reproducibility_pct` (docs/competition/scorecard.md).
  - **Blocked**: needs-real-machine-data — 2026-10-27: the 537 s apply was measured on a managed Mac, and the apply timing line shows only pull, chezmoi apply, and doctor. Finding the slow `run_after_*` scripts needs a timed full apply there (for example `chezmoi apply -v` with each script start and end time noted, or `DOTFILES_DEBUG` per-script timing). A guess at which scripts to hash-key, without that data, could skip real work. Unblock: one timed full apply on that Mac, with the per-script seconds pasted into this task.

- [ ] Checkup skips the full `dotfiles apply` when nothing changed
  - **ID**: checkup-skip-apply-when-unchanged
  - **Tags**: perf, agents
  - **Details**: The 2026-10-20 `/tooling-checkup` ran `dotfiles apply` for 191 s (last run: 214 s) right after `dotfiles-sync` printed "No changes". The apply converges drift too, so a skip must still detect drift cheaply (for example `chezmoi status` plus the doctor modules the checkup already runs).
  - **Files**: `skills/update-tooling/SKILL.md`, `skills/tooling-checkup/SKILL.md`
  - **Output**: code
  - **Acceptance**: a checkup on an unchanged machine finishes the apply step in under 30 s, and a hand edit is still reported.
  - **Hypothesis**: skipping the full apply when the source head and live drift are unchanged cuts the checkup apply step from ~200 s to under 30 s.
  - **Measurement**: the `dotfiles_apply_secs` metric in `python3 ~/.claude/skills/tooling-checkup/scripts/checkup_state.py diff`, on the next two checkups.
  - **Success**: under 30 s on a no-change run.
  - **Pivot**: over 90 s, or a missed drift item -> keep the full apply and speed up its slowest step instead.
  - **Anchor**: tooling-checkup agent time review 2026-10-20; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: `noop_reapply_ms` (docs/competition/scorecard.md).
  - **Blocked**: needs-time — 2026-10-22: shipped `dotfiles apply --if-changed` and switched update-tooling and tooling-checkup to it (PR #253). Baseline `dotfiles_apply_secs`: 191 s and 214 s on the last two checkups. The skip check took 0.74 to 1.09 s on this Mac at load1 114. Measure on the next two checkups, on or after 2026-10-29, with `python3 ~/.claude/skills/tooling-checkup/scripts/checkup_state.py diff` (`dotfiles_apply_secs`), then close or pivot.

- [ ] Make `make check` fast in the inner loop
  - **ID**: speed-up-make-check
  - **Evidence**: On Nov 6, the registered seven-day agent time review reported six Dotfiles `make check` calls totaling 1,350,074 ms, or 3.21 min/day. This exceeds the 2 min/day pivot threshold; the original approach did not meet the outcome. The local gate-timing log points to the test phase as the largest aggregate, but its rows are not bound to those six calls, so they do not establish the cause of this result.
  - **Next**: Pivot from relying on caching and steering alone. The [synthetic attribution controls](docs/plans/gate-attribution-synthetic.md) pass. Register real-agent receipt delivery before identifying the slowest contributing step and proposing a separately measured change. Keep existing caches and safety gates until a replacement is proved.
  - **Tags**: perf, agents
  - **Details**: The 2026-10-20 checkup time review: `make check` costs 2m38s/day (17x in 7 sessions, p95 5m12s). Agents run the full gate while iterating instead of `bin/bats-affected`.
  - **Files**: `Makefile`, `AGENTS.md`, `bin/cached-run`
  - **Output**: code
  - **Acceptance**: the `make check` line in the 7-day agent time review is under 1 min/day.
  - **Hypothesis**: steering the inner loop to `bin/bats-affected` and caching unchanged steps cuts `make check` from 2m38s/day to under 1 min/day.
  - **Measurement**: `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (the dotfiles `make check` line), 7 days after the change lands.
  - **Success**: under 1 min/day.
  - **Pivot**: still over 2 min/day after 7 days -> profile per step from `~/.local/state/dotfiles/gate-timings.jsonl` and drop this approach.
  - **Anchor**: tooling-checkup agent time review 2026-10-20; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: none — agent gate speed (docs/metrics.md gate row), not a scorecard metric.

- [ ] Cut the dotfiles hook wait on every agent Bash call by half
  - **ID**: rust-agent-hooks
  - **Tags**: migration, rust, performance
  - **Mode**: AFK
  - **Details**: Step 1 of the [Rust migration](docs/plans/rust-migration.md). Porting stays paused until the owner starts it. `agent-hooks/require-heavy-run.sh` and `agent-hooks/block-dangerous-git.sh` run on each agent Bash call and start Perl, `shfmt` or `jq`. First prove 20 A/A runs of the gate (base and head at the same commit) with 0 failures and commit the absolute baseline of both rows. The gate compares minimums only, so a failed A/A is a real risk. A port PR must not change a row's command path. If the PR adds Rust code, it also adds the cargo step to the Makefile, and `make check` must build Rust only when `rust/` changed. Then weigh a shell fast path that exits before any interpreter start for a command that cannot match. Port a hook to Rust only when the fast path misses the number. Keep every deny, allow and unknown verdict. The [agent-hook source receipt](docs/plans/agent-hook-source-receipt.md) lists the source boundaries.
  - **Output**: code
  - **Acceptance**: Gate G in the plan. The affected Bats tests pass with 0 changed verdicts. Hostile heredocs, substitutions and absent tools keep their result. The old script stays until rollback is proven. A Rust binary opens the deferred native delivery step first.
  - **Hypothesis**: Removing the per-call interpreter starts cuts the fastest run of each of the two hook rows by at least 50% against the merge-base, with 100% verdict parity and 0 new false permits.
  - **Measurement**: `scripts/perf-gate.sh --force --json` (rows `hook-require-heavy-run` and `hook-block-dangerous-git`) and `bin/bats-affected origin/feat/chezmoi | xargs heavy-run bats`; for peak RSS, the peak RSS command in the plan's "Commands that run today" (median of 15 runs of `/usr/bin/time -l` on the row's command), once at the base and once at the head.
  - **Success**: 20 of 20 A/A runs pass first; `ratio` at most 0.50 for both rows; affected tests 100% green; R_M (candidate median peak RSS / baseline median) at most 1.10 after an A/A ratio from 0.95 to 1.05.
  - **Pivot**: 1 or more A/A failures in 20 runs -> stop before any hook change; the result is inconclusive until task `perf-gate-paired-median-parity` lands or the run conditions are fixed, and the thresholds stay. `ratio` above 0.80 for a hook after the fast path and one port attempt -> abandon that hook's port and add it as a recorded exception row in the plan with its measured number. Any new false permit -> stop and change the parser boundary, never an allow rule.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Kohavi, Tang, Xu 2020 (A/A checks and guard metrics).
  - **Competitive-goal**: none — agent wait time and background CPU (docs/metrics.md), not a scorecard metric.

- [ ] Cut the background cost of app-priority to under half a second per run
  - **ID**: rust-app-priority
  - **Tags**: migration, rust, performance
  - **Mode**: AFK
  - **Details**: Step 2 of the [Rust migration](docs/plans/rust-migration.md). Porting stays paused until the owner starts it. The `app-priority` LaunchAgent runs every 60 seconds. The window command gave a mean of 1,560 ms over 9,674 runs for the 7 days to 2026-11-10 and 990 ms over 8,654 runs for the 7 days before. The two windows differ by 37%, so the logged mean is inconclusive today. The script calls `ps` once per process and walks parents one call at a time. `log_run` rounds to whole seconds, and about a quarter of the samples are 0. So the first PR only makes the number usable: log real milliseconds for this run. Then compare two before windows (`--argjson to 0` and `--argjson to 7`); they must differ by at most 20% of the larger. Commit the baseline from the command, not from this text. Only then read the process table in one `ps` pass. Port the scan to Rust only when that pass misses the number. Keep the same nice and QoS decisions for the same processes. Each window needs at least 1,000 runs.
  - **Output**: code
  - **Acceptance**: Gate G in the plan. `bats tests/app-priority.bats` passes with the same priority decisions on the same fixture process table. No process outside the owned rules changes priority.
  - **Hypothesis**: One process-table pass cuts the 7-day mean `app-priority` run time to at most 400 ms and at most 40% of the lower of two before windows that agree within 20%, with identical priority decisions on the fixture table.
  - **Measurement**: `jq -c -s --argjson to 0 '(now - ($to + 7) * 86400 | todate) as $a | (now - $to * 86400 | todate) as $b | [.[] | select(.task == "app-priority" and .timestamp >= $a and .timestamp < $b) | .duration_ms] | {runs: length, mean: (if length > 0 then add / length else null end), zeros: (map(select(. == 0)) | length)}' ~/.dotfiles-stats.jsonl` for the last 7 days; `--argjson to 7` gives the 7 days before. On 2026-11-10 it printed a mean of 1560.47 (9,674 runs) and, with `to` 7, 990.41 (8,654 runs).
  - **Success**: the two before windows differ by at most 20% of the larger; then the after window's mean is at most 400 ms and at most 40% of the lower before window, with at least 1,000 runs per window; 0 changed priority decisions in the Bats fixture.
  - **Pivot**: the before windows still differ by more than 20% after the millisecond log has 14 days of runs -> the mean is not a usable measure; stop and add a budget row for a fixture process table instead. After mean above 80% of the lower before window after the single `ps` pass -> build the Rust scan with its own committed number. Above 80% after that too -> abandon the port, lengthen the run interval instead, and add the slice as a recorded exception row in the plan with its measured number.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Kohavi, Tang, Xu 2020 (A/A checks and guard metrics).
  - **Competitive-goal**: none — agent wait time and background CPU (docs/metrics.md), not a scorecard metric.

- [ ] Find out where doctor, apply and sync time goes before any port
  - **ID**: rust-cold-path-profile
  - **Tags**: migration, rust, performance, measurement
  - **Mode**: AFK
  - **Details**: Step 3 of the [Rust migration](docs/plans/rust-migration.md). The validation review did not profile doctor probes, apply, sync, upgrade or the queue. They are recorded exceptions until a profile shows owned code is the cost. Time each command on fixtures in a scratch HOME with wall-clock spans around child calls. Split wall time into owned shell, git, network and child tools. Put the result next to the command's local p50. Write the table into the plan. Port nothing.
  - **Output**: measurement
  - **Acceptance**: The plan has one row per profiled command: local p50, share of wall time in owned code, and the decision (stays an exception, or reopens with a number). Every reopened slice gets its own task block with the rule-9 fields.
  - **Hypothesis**: Owned shell code is under 50% of wall time in at least 80% of the profiled command families, so those stay recorded exceptions and no port starts on a guess.
  - **Measurement**: `jq -s '[.[] | select(.command == "doctor") | .duration_ms] | sort | .[length / 2 | floor]' ~/.local/state/dotfiles/commands.jsonl` per command for the local p50 (it printed `null` on 2026-11-10; it prints `null` until the command has logged runs), and the span timings from the registered fixture run for the share.
  - **Success**: 100% of the listed command families have a profile row and a decision in the plan.
  - **Pivot**: If spans cannot separate child-tool time from owned time in 2 or more families -> record those families as "not separable" exceptions and stop; do not estimate.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — agent wait time and background CPU (docs/metrics.md), not a scorecard metric.

- [ ] Account for every executable with a manifest and a thin validator adapter
  - **ID**: rust-source-inventory
  - **Tags**: migration, rust
  - **Mode**: AFK
  - **Details**: Step 4 of the [Rust migration](docs/plans/rust-migration.md). Porting stays paused until the owner starts it. Deliver the component manifest and a thin pinned Rust adapter to agentbrew's small inventory validator. No full harness. Each owned executable gets one of five states: `ported`, `exception` (with its row in the plan), `frozen`, `grandfathered` (the fixture crates that shipped before gate G) or `out-of-scope` (UI presentation and shell that must stay shell). Embedded interpreters, extensionless tools and generated code must not escape. Pin the shared crate by git `rev` and vendor it, as the plan's cross-repo rule says. This step ports nothing, so only the parity and safety clauses of gate G apply to it. The [reviewed source collection](docs/plans/rust-source-inventory.md) records the completed families and remaining coverage.
  - **Output**: code
  - **Blocked**: needs-agentbrew-inventory — the validator in agentbrew task `rust-source-inventory` must merge before the adapter check can pass. Source collection proceeds now. No other dotfiles step waits for agentbrew.
  - **Acceptance**: Unclassified owned executable components 0; every component has one owner and one of the five states. The validator rejects every planted embedded, extensionless and generated-code omission. `cargo build --locked --offline` works from the vendored copy.
  - **Hypothesis**: A source-and-caller inventory makes unclassified owned executable components reach 0, including extensionless and embedded code, without changing runtime behavior.
  - **Measurement**: `heavy-run cargo build --locked --offline --release --manifest-path rust/Cargo.toml --bin migration-check && heavy-run rust/target/release/migration-check inventory --check` — runnable after the agentbrew inventory step merges and this adapter pins it, not before.
  - **Success**: Unclassified owned executable components 0; unrecorded exceptions 0; every planted omission rejected; cold build at most 120 s.
  - **Pivot**: Any missed component or blanket exception changes the inventory method to execution/caller analysis before a replacement starts.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Forsgren, Humble, Kim 2018 (performance and stability).
  - **Competitive-goal**: none — agent wait time and background CPU (docs/metrics.md), not a scorecard metric.

- [ ] Prove every owned executable has one of the five audit states
  - **ID**: rust-final-audit
  - **Tags**: migration, rust
  - **Mode**: AFK
  - **Details**: Step 5 of the [Rust migration](docs/plans/rust-migration.md). Reconcile the manifest, each ported slice's receipts, generated and installed entrypoints and docs. Retire only proven unused implementations. The five audit states (`ported`, `exception`, `frozen`, `grandfathered`, `out-of-scope`) are a default adopted on 2026-11-10; the owner has not ruled on them. A slice that ended at its Pivot counts as `exception`. The audit claims "all measured hot paths ported". It never claims "all code is Rust".
  - **Output**: measurement
  - **Blocked by**: rust-agent-hooks, rust-app-priority, rust-cold-path-profile, rust-source-inventory
  - **Blocked**: needs-owner — the owner rules on the defaults in the plan's "Decisions (2026-11-10)" and on the five audit states. The agentbrew task `rust-owner-rules-on-replan-defaults` (HITL) tracks that ruling for both plans.
  - **Acceptance**: Every owned component in the manifest has one of the five states; `ported` has receipts and `exception` has a plan row. Every ported slice still meets its number on the current tree. No temporary bridge remains without a deletion condition.
  - **Hypothesis**: Reconciling the manifest with the tree exposes every gap: 0 unrecorded owned components, and 100% of ported slices still at or under their registered number.
  - **Measurement**: `heavy-run rust/target/release/migration-check inventory --check` (runnable after the inventory step merges), `scripts/perf-gate.sh --force --json` and `heavy-run make check`.
  - **Success**: 0 unrecorded components; 100% of ported rows pass the gate; `heavy-run make check` green.
  - **Pivot**: Any unrecorded component or failed ported row -> the migration stays open; fix that boundary. Do not change the goal to converted lines.
  - **Anchor**: Basili, Caldiera, Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration); Kohavi, Tang, Xu 2020 (A/A checks and guard metrics).
  - **Competitive-goal**: none — agent wait time and background CPU (docs/metrics.md), not a scorecard metric.

- [ ] Stop the pre-push leak check flagging a public github.com URL pattern as a private ssh host
  - **ID**: pre-push-ssh-host-false-alarm-escaped-regex
  - **Tags**: git-hooks, privacy, reliability
  - **Details**: On 2026-11-10 the pre-push hook blocked a push of PR #562 (send anonymous performance telemetry by default). The flagged line was a bash regex for the public upstream repo URL. Its third alternative was `ssh://` followed by `git@github\.com/` (the dot is escaped for the regex). `lib/private-ref-markers.awk` (the `ssh host` rule) reads the host as the letters up to the backslash, so it sees `github`, which is not on its public-host list, and reports a private host. Exact hook output: `✗ 2 private reference(s) in lines or messages of pushed commits:` / `   0aecf8c: ssh host` / `   9e36e83: ssh host` / `Use placeholders: ~ for a home dir, github.example.com for a host. Then rewrite those commits.` / `push blocked by dotfiles pre-push hook` / `If a person checked it: dotfiles leak allow --once <commit sha>, in a terminal.` The false alarm forced a code change (the host moved into a variable) and a rewrite of three unpushed commits. The hook must stay fail-closed for a real private host.
  - **Files**: `lib/private-ref-markers.awk`, `tests/gh-wrapper-leak-guard.bats`, `docs/privacy-gates.md`.
  - **Output**: code
  - **Acceptance**: a failing test first: feed the awk rule one line that holds the ssh scheme form of the public github.com repo URL with the dot escaped by a backslash (a regex), and assert no `ssh host` hit; then the same line with a made-up private host and an escaped dot, and assert one hit. Both the escaped and the plain form of github.com, gitlab.com, bitbucket.org, and codeberg.org pass; every existing private-host test still fails closed.
  - **Hypothesis**: reading an escaped dot as a dot in the ssh-host rule moves false alarms on public-host regexes from 1 known case to 0 with no lost true hit.
  - **Measurement**: `bats tests/gh-wrapper-leak-guard.bats`, with the two new cases.
  - **Success**: 0 hits on the public escaped form and 1 hit on the private escaped form; all older cases unchanged.
  - **Pivot**: if any older private-host case stops failing closed, drop the change and document the workaround (keep the host in a variable) in `docs/privacy-gates.md` instead.
  - **Anchor**: PR #562 push block on 2026-11-10; Basili, Caldiera and Rombach (1994), Goal Question Metric.
  - **Competitive-goal**: none — correctness of an existing privacy gate, not a scorecard metric.

## P3

- [ ] Harden the tooling-checkup dashboard chart checks (round-2 review of dotfiles #379)
  - **ID**: dashboard-chart-gate-hardening
  - **Blocked**: needs-deployed-test-host — 2026-11-01: runtime and browser-gate changes are prepared together but excluded from ready delivery. The existing dashboard remained on a browser-verification page after more than 120 seconds, and no Dashboard writer capability is available. Synthetic-host screenshots are unit proof only. Unblock: use an accessible dedicated deployed test dashboard with fabricated datasets; capture labeled before/after proof for hourly binding and line contrast on phone/desktop in light/dark, then complete independent review and required local gates. Keep [draft PR #423](https://github.com/fyodoriv/dotfiles/pull/423) as a draft until then. Its local full gate exited 0 and all 11 browser controls passed; these do not replace deployed-host proof.
  - **Tags**: ui, tooling-checkup
  - **Details**: Four leftovers from the round-2 review of the Hallmark dashboard redesign. (1) The load chart can show a duplicate or a missing local hour on a daylight-saving change, because the exporter keys rows by local time: key them by UTC and format in the page. (2) The gate's tap test uses a mouse click, not `touchscreen.tap`. (3) The gate presses ArrowLeft but never checks that the tooltip moved. (4) Chart line colours (non-text contrast, WCAG 1.4.11) are not gated.
  - **Files**: `skills/tooling-checkup/scripts/dashboard_export.py`, `skills/tooling-checkup/dashboard/index.html`, `skills/tooling-checkup/scripts/dashboard_comfort.cjs`, `tests/tooling-checkup-dashboard.bats`
  - **Output**: code
  - **Acceptance**: a fixture with a spring-forward and a fall-back week draws 168 distinct hours; the gate taps with `touchscreen.tap`, asserts the tooltip text changes after ArrowLeft, and fails on a chart line under 3:1 against the panel in light and dark.

- [ ] Keep the time of the telemetry yes, not only its day
  - **ID**: telemetry-consent-time-for-install-event
  - **Tags**: telemetry, privacy
  - **Details**: The state file keeps the day of the yes (`consent_at`). The `dotfiles.install` event is sent when the install finished on or after that day. So an install that finished some hours before a yes on the same UTC day is sent too. The owner accepted the day rule on 2026-11-10. A stored time would make the rule exact. `lib/stats.sh` reads the state line with string patterns, so keep the old field and add a new one.
  - **Files**: `bin/dotfiles-telemetry`, `tests/telemetry-gains.bats`, `docs/observability.md`
  - **Output**: code
  - **Acceptance**: a bats test with an install that finished one hour before the yes on the same day sends no install event; a state file without the new field still works with the day rule.
  - **Hypothesis**: the longest time before a yes from which an install event can still be sent goes from 24 hours to 0.
  - **Measurement**: `heavy-run bats tests/telemetry-gains.bats tests/telemetry.bats`
  - **Success**: the new test passes (red before the change), and every older test passes.
  - **Pivot**: the new field breaks the string patterns in `lib/stats.sh` -> keep the day rule and close.
  - **Anchor**: Munafò et al. 2017 (pre-registration); Basili, Caldiera and Rombach 1994 (GQM).
  - **Competitive-goal**: none — consent precision, not a scorecard metric.

- [ ] Show the gain events on the maintainer's private PostHog dashboard
  - **ID**: telemetry-gains-dashboard-tiles
  - **Tags**: telemetry, metrics, owner
  - **Details**: The sender now sends `dotfiles.install` (`seconds`, `ok`, `profile`) and `dotfiles.gains` (`zsh_ms_before`, `zsh_ms_now`, `zsh_min_ms_now`, `zsh_min_ms_stock`, `days_since_install`; with no install receipt only the three numbers measured in the send), and `dotfiles.run` carries `seconds_saved` (an estimate). The tiles exist since 2026-11-10 and `docs/observability.md` lists them ("Product tiles on the dashboard"); the saved-minutes tile has data, and the time-to-configured and shell-start tiles are empty because no install with a receipt has sent an event yet. What is left: read the two tiles after the first such install; add the install success rate per profile (the time-to-configured tile counts `finished_ok` over all profiles only); then close this task. The shell-start tile reads medians and the default-Mac pair since 2026-11-10. Original plan: add tiles to the private dashboard: median time to configured and install success rate per profile; median shell start before and now, per install and over all installs; the sum of estimated saved seconds per install and in total. Label the saved seconds as an estimate. The README Proof row for the install is a separate task (`proof-install-field-outcome`); the install receipt can feed it.
  - **Files**: the PostHog project (owner), `docs/observability.md`
  - **Output**: dashboard, docs
  - **Acceptance**: the dashboard shows each tile with data from one real install or more; `docs/observability.md` lists the tiles.
  - **Hypothesis**: the gain questions that the dashboard answers (time to configured, shell start gain, saved time) go from 0 to 3.
  - **Measurement**: the HogQL query `select event, count() from events where event in ('dotfiles.install', 'dotfiles.gains') group by event` returns both events.
  - **Success**: all 3 questions have a tile with data.
  - **Pivot**: no install sends a gains event in 30 days -> check the consent rate first and close this task.
  - **Anchor**: Basili, Caldiera and Rombach 1994 (GQM); Forsgren, Humble and Kim 2018 (*Accelerate*).
  - **Competitive-goal**: none — proof of field gains, not a scorecard metric.

- [ ] Telemetry notices an unusable state folder, and cuts the log beside an unreadable state file
  - **ID**: telemetry-state-folder-and-unreadable-cap
  - **Tags**: telemetry, doctor
  - **Details**: Two leftovers from the 2026-11-10 review of the telemetry follow-ups. (1) The doctor check `chezmoi.telemetry_state_readable` passes when the state folder itself is root-owned with mode 700: the file test then says "absent", while telemetry can read and write nothing. (2) With a state file that exists but cannot be read, `_commands_log_cap` starts `dotfiles-telemetry cap-commands`, which cuts nothing, so `commands.jsonl` grows until the user fixes the file.
  - **Files**: `modules/chezmoi/doctor.sh`, `lib/stats.sh`, `tests/telemetry.bats`, `docs/observability.md`
  - **Output**: code
  - **Acceptance**: a bats test with a state folder the user cannot enter makes the doctor check fail with the fix command; a bats test with an unreadable state file and a log over the cap ends with a log at the cap.
  - **Hypothesis**: the two cases where telemetry state is unusable without a report or a log cut go from 2 to 0.
  - **Measurement**: `heavy-run bats tests/telemetry.bats`
  - **Success**: both new tests pass (red before the fix), and every older test passes.
  - **Pivot**: the folder check needs a root-only fixture or grows past a small helper -> document the case in `docs/observability.md` and close.
  - **Anchor**: review of the telemetry follow-ups, 2026-11-10; Basili, Caldiera and Rombach 1994 (GQM).
  - **Competitive-goal**: none — telemetry robustness, not a scorecard metric.

- [ ] `hotfix` finds the default branch of a repo whose default is not `main`
  - **ID**: hotfix-default-branch-without-origin-head
  - **Tags**: git, workflow
  - **Details**: Found on 2026-11-10, when the hosted check first ran `tests/hotfix.bats` on a clean machine. `bin/hotfix` reads the default branch from `origin/HEAD` and falls back to `main` when that ref is not set. In a repo whose default branch is `master` and that has no `origin/HEAD`, `hotfix` fails. The tests now set the branch name to `main`, so no test covers this case.
  - **Files**: `bin/hotfix`, `tests/hotfix.bats`
  - **Output**: code
  - **Acceptance**: a bats test with a `master`-only repo and no `origin/HEAD` creates the hotfix branch from `master`.
  - **Hypothesis**: `hotfix` runs that fail in a `master`-only repo without `origin/HEAD` go from every run to 0.
  - **Measurement**: `heavy-run bats tests/hotfix.bats`
  - **Success**: the new test passes (red before the fix), and every older test passes.
  - **Pivot**: the lookup needs a network call -> print a clear error that names the fix (`git remote set-head origin -a`) and close.
  - **Anchor**: review of the hosted-runner test fix, 2026-11-10; Basili, Caldiera and Rombach 1994 (GQM).
  - **Competitive-goal**: none — workflow robustness, not a scorecard metric.

- [ ] Make `make lint` fast in the inner loop
  - **ID**: speed-up-make-lint
  - **Blocked**: needs-time — 2026-10-22: shipped `make lint` per-file cache (`bin/cached-run --per-file`: skips a script that passed with the same content, sourced files, shellcheck version, and `.shellcheckrc`; shared by all worktrees; misses run in parallel) plus `make lint-full` (PR #257). Baseline 2026-10-22: `make lint` lines sum 6m02s/day (tooling 2m08s, dotfiles 2m04s, agentbrew 1m50s); one run 17-39 s uncached, now 11.6 s cold and 1.2-1.3 s warm at load 40-50. Measure on or after 2026-10-29 with `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (sum of the `make lint` lines), then close or pivot.
  - **Tags**: perf, agents
  - **Details**: The 2026-10-21 checkup time review (7 days): `make lint` (shellcheck on every script in `SCRIPTS`) costs 3m51s/day across sessions started in dotfiles and agentbrew (14x in 4 sessions, p95 8m20s to 11m30s). agentbrew has no Makefile, so both lines are this target. Agents run the full shellcheck while they iterate.
  - **Files**: `Makefile`, `bin/cached-run`, `AGENTS.md`
  - **Output**: code
  - **Acceptance**: the `make lint` lines in the 7-day agent time review add up to less than the Success threshold.
  - **Hypothesis**: shellcheck on changed scripts only (or `bin/cached-run` per file) cuts `make lint` from 3m51s/day to under 1 min/day.
  - **Measurement**: `python3 ~/.claude/skills/tooling-checkup/scripts/agent_time_review.py --days 7` (sum of the `make lint` lines), 7 days after the change lands.
  - **Success**: under 1 min/day.
  - **Pivot**: still over 3 min/day after 7 days -> profile with `bin/dotfiles-metrics --table` gate rows and drop this approach.
  - **Anchor**: tooling-checkup agent time review 2026-10-21; Forsgren, Humble, Kim 2018 (lead time); perf-review skill known fixes.
  - **Competitive-goal**: none — agent gate speed (docs/metrics.md gate row), not a scorecard metric.

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

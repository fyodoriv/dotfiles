# Plan: one-command-whole-machine-update

## Goal
Add one obvious whole-machine update entry point that reconciles the dotfiles source, reapplies chezmoi lifecycle hooks, delegates agent-config refresh to agentbrew, runs the existing package/toolchain upgrade wrapper, and finishes with doctor checks behind a concise phased CLI.

## Why
This implements `TASKS.md` P0 `one-command-whole-machine-update` and traces to:
- Vision goal: `VISION.md` G1 — Self-healing > documented manual steps, and G2 — agent config is agentbrew’s job, not dotfiles’. Dotfiles should orchestrate its own source/apply/doctor surfaces and call agentbrew only as the owner CLI for generated agent config.
- User story: `docs/user-stories/02-start-day-ready-to-code.md` / US-02 — the machine should be pulled, healthy, and visible through one command or automation; `docs/user-stories/05-config-heals-itself.md` / US-05 — config should stay in sync and self-heal without remembered manual maintenance.
- Competitor prior art: N/A — this is host-local dotfiles orchestration over existing CLIs, not a market-facing feature; the relevant “prior art” is already in-repo: `chezmoi apply`, `.chezmoiscripts/run_after_agentbrew-sync.sh`, `bin/dotfiles-upgrade` wrapping topgrade, `agentbrew sync --pull`, and `dotfiles-doctor`.

## Scope (in)
- Add `bin/dotfiles-update` as a thin orchestrator with clear phase output.
- Route `dotfiles update` through the new orchestrator while preserving `dotfiles apply --pull` for users who only want source pull + apply.
- Implement `--dry-run` so it lists every phase and the exact command shape without mutating state.
- Implement `--verbose` for command echoing and detailed phase boundaries.
- Run phases in this order:
  1. pull the dotfiles git source with `git pull --rebase`,
  2. run `dotfiles apply` so chezmoi lifecycle scripts update Homebrew bundle content, macOS defaults, LaunchAgents, overlay hooks, shell caches, uv/python setup, and baseline agentbrew sync,
  3. delegate the agent-config source refresh to agentbrew with `agentbrew sync --pull --agentfile "$DOTFILES_DIR/Agentfile.yaml"`, when agentbrew is available,
  4. run `dotfiles-upgrade` so topgrade handles package managers and language toolchains instead of reimplementing them,
  5. run `dotfiles-doctor --fix` as the final self-healing gate.
- Preserve the ownership boundary: the new script never edits `~/.claude/`, `~/.cursor/`, `~/.config/devin/`, or other generated mirrors directly. It only invokes the existing owner CLI (`agentbrew`) in the same way `run_after_agentbrew-sync.sh` already does, adding `--pull` because the task explicitly requires agentbrew source/skill/MCP/rule/command refresh and the current agentbrew CLI exposes that evergreen source-refresh path.
- Keep phase failures actionable: stop at the failing phase, print the phase name and exit code, and leave later phases unrun.
- Add focused Bats coverage in `tests/bin-dotfiles-update.bats` for phase ordering, dry-run behavior, and failure reporting.
- Update README, AGENTS.md, CLAUDE.md, and CLI help so “update this machine” names exactly one command and documents the agentbrew delegation boundary.
- Remove the completed task block from `TASKS.md` in the implementation commit and add scout follow-ups if implementation reveals nearby gaps.

## Scope (out)
- Do not reimplement Homebrew, npm, pipx, uv, fnm, gh extension, JetBrains, VS Code, or Ollama upgrade logic. `bin/dotfiles-upgrade` already delegates that to topgrade.
- Do not edit generated agent config under `~/.claude`, `~/.cursor`, `~/.config/devin`, or other agent mirrors.
- Do not add org-specific update phases or internal endpoints to the base repo. Overlay-owned work stays in the overlay Agentfile/scripts.
- Do not make the command silently ignore failed phases. Nonzero actionable failures should stop the run.
- Do not add destructive cleanup, branch resets, or protected-branch pushes.
- Do not change weekly LaunchAgent scheduling in this task; this is the manual one-command path.

## GET-before-IMPLEMENT decision
- GET: Use existing tools for the heavy work: `git pull --rebase`, `dotfiles apply`/chezmoi lifecycle, `agentbrew sync --pull`, `bin/dotfiles-upgrade`/topgrade, and `bin/dotfiles-doctor --fix`.
- WRAP: Add a small shell orchestrator because the missing capability is sequencing, dry-run visibility, and unified failure reporting across those existing commands. This is an adapter over existing tools, not a package manager or agent-sync implementation.
- CONTRIBUTE: No upstream contribution is needed; the upstream tools already expose the commands required.
- ABSORB: The only bespoke code is phase orchestration and CLI output. If it grows into a broader workflow engine, file a Replace? Relocate? follow-up for agentbrew/minsky/topgrade rather than expanding dotfiles.

## Implementation steps
1. Add failing tests in `tests/bin-dotfiles-update.bats`:
   - Test `normal run executes phases in order`: create a temp stub bin directory; each stub appends its name and args to `$TEST_DIR/invocations`; run `PATH="$stub_bin:$PATH" bin/dotfiles-update`; assert the file equals:
     ```
     git -C <repo> pull --rebase
     dotfiles apply
     agentbrew sync --pull --agentfile <repo>/Agentfile.yaml
     dotfiles-upgrade
     dotfiles-doctor --fix
     ```
   - Test `dry-run prints phases without executing`: run `bin/dotfiles-update --dry-run`; assert no invocation file exists and output contains these exact command lines, each prefixed by `DRY-RUN:`:
     ```
     DRY-RUN: git -C <repo> pull --rebase
     DRY-RUN: dotfiles apply
     DRY-RUN: agentbrew sync --pull --agentfile <repo>/Agentfile.yaml
     DRY-RUN: dotfiles-upgrade
     DRY-RUN: dotfiles-doctor --fix
     ```
   - Test `phase failure stops later phases`: make the `dotfiles apply` stub exit 42; assert `bin/dotfiles-update` exits nonzero, output contains `✗ Phase failed: apply (exit 42)`, and invocation log contains only git + apply.
   - Test `missing agentbrew skips refresh`: omit the `agentbrew` stub while other stubs succeed; assert output contains `○ agentbrew not available — skipping agent config refresh` and later package/doctor phases still run.
2. Implement `bin/dotfiles-update`:
   - strict bash mode and standard `--help`, `--dry-run`, `--verbose` parsing,
   - resolve `DOTFILES_DIR` from the script path,
   - phase helper that prints `→`, `✓`, `○`, and `✗` status lines consistently with existing scripts,
   - dry-run helper that prints the exact command line prefixed with `DRY-RUN:`,
   - agentbrew phase that prefers `bin/agentbrew` when executable, then PATH `agentbrew`, and skips when unavailable,
   - no global lock, so nested `dotfiles-upgrade` and `dotfiles-doctor` can acquire their own locks normally.
3. Update `bin/dotfiles`:
   - Common help line becomes `update [--dry-run] [--verbose]  Update the whole machine (pull/apply/agents/packages/doctor)`,
   - `apply` help keeps `--pull` documented as the narrow source/apply path,
   - Advanced help removes the old `update Alias of apply --pull` line,
   - `update)` delegates to `bin/dotfiles-update "$@"`, preserving pass-through flags.
4. Update README:
   - In “Apply and update”, replace `dotfiles update # pull latest + re-apply` with `dotfiles update # whole-machine update: pull/apply/agentbrew/packages/doctor`, and add `dotfiles apply --pull # narrow path: pull dotfiles source + apply only`.
   - In CLI reference, change the update line to `dotfiles update [--dry-run] [--verbose]        Whole-machine update (pull/apply/agentbrew/packages/doctor)` and keep `dotfiles upgrade [--dry-run]` as the package-only/topgrade wrapper.
   - In AI agent config, add one sentence: `dotfiles update` delegates agent-source refresh to `agentbrew sync --pull --agentfile ~/apps/dotfiles/Agentfile.yaml`; agentbrew remains the owner of generated agent config.
5. Update AGENTS.md and CLAUDE.md:
   - Add a short “Whole-machine update boundary” note near Agentfile Lifecycle/Rules for Editing: `dotfiles update` may invoke `agentbrew sync --pull --agentfile Agentfile.yaml` as a delegation to the owner CLI, but dotfiles must not edit generated agent config directly.
6. Remove the task block from `TASKS.md`; add a scout follow-up if implementation exposes a concrete adjacent gap.
7. Verify with focused Bats, `make lint-tasks`, and `make check` before shipping.

## Risks and mitigations
- Risk: `dotfiles update` becomes too broad for users who expected only `git pull + apply`. Mitigation: keep `dotfiles apply --pull` unchanged and document it as the narrow source/apply path; `dotfiles update` is the explicit whole-machine command from this task.
- Risk: nested locks cause `dotfiles-upgrade` or doctor to skip. Mitigation: the orchestrator does not acquire the shared dotfiles lock; subcommands keep owning their lock behavior.
- Risk: running topgrade during a minsky loop or active dev session is disruptive. Mitigation: reuse `bin/dotfiles-upgrade`, whose existing minsky-loop safety and topgrade flags already own that policy.
- Risk: agentbrew is unavailable on non-AI machines. Mitigation: skip the explicit agentbrew refresh with a clear status line; `dotfiles apply` remains non-fatal for agentbrew as today.
- Risk: duplicate agentbrew sync work. Mitigation: `dotfiles apply` keeps the baseline Agentfile sync; the explicit post-apply `agentbrew sync --pull --agentfile ...` is the owner-tool source-refresh path required by this task and available in the current agentbrew CLI.

## Acceptance criteria
- `bin/dotfiles-update --dry-run` prints every phase in order with `DRY-RUN: <command>` lines and does not run mutating commands.
- `dotfiles update` invokes `bin/dotfiles-update` and preserves pass-through flags.
- A normal run executes pull → apply → `agentbrew sync --pull --agentfile <repo>/Agentfile.yaml` when available → upgrade → doctor in order.
- An actionable phase failure exits nonzero, names the failed phase and exit code, and does not run later phases.
- README, AGENTS.md, and CLAUDE.md document that agentbrew refresh is delegated to agentbrew and generated agent config remains outside dotfiles ownership.
- `make check` passes.
- README’s “update this machine” path names exactly one command: `dotfiles update`.
- The `one-command-whole-machine-update` task block is removed from `TASKS.md` in the implementation commit.

## Reviewer verdict
- **Verdict**: needs-revision
- **Reviewer**: code-reviewer
- **Date**: 2026-06-11
- **Concerns**:
  - **Ownership boundary ambiguity (VISION.md G2 violation)**: Plan proposes `dotfiles-update` to invoke `agentbrew sync --pull`, but VISION.md G2 and AGENTS.md state "agent config is agentbrew's job, not dotfiles'". The plan acknowledges "duplicate agentbrew sync work" but justifies it as "required by tooling delivery mandate" — this mandate is not cited in VISION/ROADMAP/AGENTS. Before implementation, clarify: does dotfiles orchestrate agentbrew sync, or does agentbrew own the entire refresh phase? If dotfiles calls agentbrew, update AGENTS.md to document the boundary and cite the mandate.
  - **Acceptance criterion ambiguity**: "agentbrew refresh when available" is undefined. The `.chezmoiscripts/run_after_agentbrew-sync.sh` already runs `agentbrew sync --agentfile` (non-fatal) during `dotfiles apply`. Specify what "refresh" means exactly: `agentbrew sync --pull`? `agentbrew sync`? What does it add beyond the baseline sync?
  - **Help text and README not specified**: Plan requires updating help text and README but does not specify the exact text. Current `bin/dotfiles` help says update is an alias of apply --pull; this is backwards if `update` becomes the primary command. Specify the new help text and README section with examples before implementation.
  - **Missing AGENTS.md update**: Plan does not mention updating AGENTS.md to document the new orchestrator command's scope and agentbrew ownership boundary. AGENTS.md rule 8 ("Agent config is managed by agentbrew, not dotfiles") should be reinforced with a note on the new command.
  - **Test specification incomplete**: Implementation step 1 lists test cases but does not specify exact stub behavior, assertion format, or expected output. Specify the exact test cases with examples: (a) normal run with all phases succeeding, (b) dry-run output format, (c) early phase failure stops later phases, (d) missing agentbrew is skipped.
  - **Dry-run output format unspecified**: Plan says `--dry-run` "lists every phase and creates no invocation log" but does not specify the exact output format. Should it print the exact command that would run (e.g., `git pull --rebase`) or just phase names? Specify with an example.

## Revision notes
- Clarified that dotfiles does not own generated agent config; `dotfiles update` delegates source refresh to agentbrew’s owner CLI and never edits generated mirrors directly.
- Specified the exact agentbrew refresh command: `agentbrew sync --pull --agentfile "$DOTFILES_DIR/Agentfile.yaml"`.
- Added exact CLI help text and README text changes.
- Added AGENTS.md and CLAUDE.md documentation updates for the whole-machine update boundary.
- Specified Bats stubs, invocation-log assertions, failure output, missing-agentbrew behavior, and dry-run output format.

## Reviewer verdict
- **Verdict**: approved
- **Reviewer**: code-reviewer
- **Date**: 2026-06-11
- **Concerns**: None

# Plan: attach-first-browser-policy-wrapper

## Goal
Make dotfiles-owned `agent-browser` shell behavior and health checks prefer attach-first browser automation for agent sessions, using the existing launchd-managed Chrome instances on ports `9223`, `9224`, and `9225` instead of spawning per-agent Chrome instances by default.

## Why
This implements `TASKS.md` P0 `attach-first-browser-policy-wrapper` and traces to:
- Vision goal: `VISION.md` G1 — Self-healing > documented manual steps, and G2 — dotfiles owns shell/doctor/Agentfile while agentbrew owns generated agent config.
- User story: `docs/user-stories/02-start-day-ready-to-code.md` / US-02 — persistent browser automation should be ready at login; `docs/user-stories/05-config-heals-itself.md` / US-05 — doctor checks should detect recurring drift.
- Competitor prior art: N/A — this is host-local dotfiles policy, but the task already cites ecosystem practice from Playwright/browser-context and browserless/orchestrator patterns: share a browser instance and isolate by context/tab unless credentials require a separate profile.

## Scope (in)
- Update `home/zshrc.ai-tools` so agent contexts do not default to spawning isolated Chrome instances for ordinary `agent-browser` calls.
- Preserve the existing safe singleton preflight behavior for any explicit `AGENT_BROWSER_PROFILE`.
- Route default/session agent calls through the managed dashboard CDP endpoint on port `9223` when reachable, unless the caller passes an explicit session/profile or opts out for a genuinely isolated non-SSO workflow.
- Add documented escape hatches for explicit isolated sessions and task-local non-SSO browser launches.
- Add or update doctor checks so drift is visible when the wrapper no longer encodes attach-first behavior or when too many remote-debugging Chrome instances are running.
- Update AGENTS.md/README docs to describe attach-first, own-tab discipline, stable purpose sessions, and the managed port mapping.
- Add Bats coverage for wrapper attach behavior in agent contexts and doctor wiring.

## Scope (out)
- Do not change upstream `agent-browser` behavior.
- Do not kill, close, or restart live browser processes.
- Do not implement CDP BrowserContext isolation in this task; it remains the pivot if tab collisions resurface.
- Do not alter other repos' docs/skills here; this task only aligns dotfiles with already-shipped attach-first wording.
- Do not remove the singleton preflight/reap helpers from the previous task.

## GET-before-IMPLEMENT decision
- GET: Reuse existing launchd Chrome endpoints and `agent-browser --cdp`; no new browser manager is needed.
- WRAP: Keep the policy in the existing zsh wrapper because the unsafe/default behavior originates from shell environment selection (`AGENT_BROWSER_SESSION`, `AGENT_BROWSER_PROFILE`, `AGENT_BROWSER_NO_AUTO_CDP`).
- CONTRIBUTE: No upstream agent-browser change is required for this local launch policy.
- ABSORB: The only bespoke code should be small wrapper branching and doctor assertions. If it grows into a policy engine, file a relocate/replace task for agentbrew or upstream agent-browser.

## Implementation steps
1. Add failing Bats coverage in `tests/zshrc-ai-tools-agent-browser.bats` for agent-context attach-first behavior:
   - Mock a responsive `127.0.0.1:9223` probe and prove a Devin/Claude/Cursor/Windsurf/Codex context with no explicit profile calls `agent-browser --cdp 9223 ...`.
   - Prove explicitly supplied `AGENT_BROWSER_SESSION` remains an isolated-session escape hatch and calls plain `agent-browser ...`.
   - Prove `AGENT_BROWSER_NO_AUTO_CDP=1` still opts out of auto-attach but does not bypass singleton preflight for managed profiles.
2. Update `home/zshrc.ai-tools` minimally:
   - Preserve explicit managed-profile preflight.
   - Make attach-first the default for agent contexts and the default session when port `9223` is reachable.
   - Keep isolated session behavior only when the caller explicitly asks for it.
3. Extend `modules/agent-browser/doctor.sh` and `tests/module-agent-browser.bats`:
   - Rename or adjust the existing `agent-browser.cdp_wrapper` check so it asserts attach-first behavior for agent contexts, not just default session.
   - Add a deterministic check that fails when the count of running Chrome remote-debugging processes exceeds the documented managed threshold; mock `ps` in Bats so the check is not host-state dependent.
4. Update docs:
   - Add an explicit `AGENTS.md` attach-first browser policy section that names ports `9223`/`9224`/`9225`, own-tab discipline, stable purpose-named session guidance, and isolated-session escape hatches.
   - Update `README.md` AI tooling env table and LaunchAgent section with the same operator-facing policy.
   - Update module/reference docs only if the wrapper semantics are described there.
5. Remove the completed task block from `TASKS.md` in the implementation commit and preserve unrelated task edits. Keep/add scout follow-ups only if implementation discovers policy that belongs in agentbrew or upstream.
6. Run focused Bats and `make check`.

## Risks and mitigations
- Risk: shared Chrome tab collisions return. Mitigation: document own-tab discipline and keep explicit isolated session escape hatch; pivot to CDP BrowserContext isolation if collisions are observed.
- Risk: SSO tasks that require a visible browser accidentally attach headless. Mitigation: docs should require `--headed` or the managed visible launchd Chrome for human-authenticated flows.
- Risk: wrapper tests become brittle against zsh syntax. Mitigation: tests continue extracting only the `agent-browser()` function and mock `command agent-browser` behavior without launching Chrome.
- Risk: process-count doctor check is noisy. Mitigation: set threshold around documented managed ports and make the message actionable; do not kill processes automatically.

## Acceptance criteria
- `make check` passes.
- `tests/zshrc-ai-tools-agent-browser.bats` covers agent-context attach-first and explicit isolation opt-out.
- `modules/agent-browser/doctor.sh` warns/fails when remote-debugging Chrome process count exceeds the documented threshold.
- `AGENTS.md` and `README.md` describe attach-first browser policy, managed ports, own-tab discipline, and explicit isolated-session escape hatches.
- The `attach-first-browser-policy-wrapper` task is removed from `TASKS.md` in the implementation commit.

## Reviewer verdict
- **Verdict**: needs-revision
- **Reviewer**: reviewer
- **Date**: 2026-06-11
- **Concerns**:
  - Missing Bats tests for attach-first behavior in agent contexts (plan step 1, TASKS.md acceptance criterion)
  - Missing process-count doctor check for remote-debugging Chrome instances (plan step 3, TASKS.md acceptance criterion)
  - AGENTS.md lacks explicit "attach-first browser policy" section describing managed ports, own-tab discipline, and escape hatches (plan step 4)
  - README.md updates not yet applied (plan step 4 lists it as required)
  - Task removal from TASKS.md not yet done (plan step 5)
  - Plan is sound and implementable, but implementation is incomplete relative to stated acceptance criteria

## Revision notes
- Made each reviewer concern an explicit implementation gate in steps 1, 3, 4, and 5.
- Clarified that process-count coverage must be Bats-mocked so the doctor check is deterministic.
- Clarified that task removal happens in the implementation commit, not in the planning commit.

## Reviewer verdict
- **Verdict**: approved
- **Reviewer**: reviewer
- **Date**: 2026-06-11
- **Concerns**: None

# Plan: agent-browser-singleton-safe-launch

## Goal
Make dotfiles-owned agent-browser launch surfaces singleton-safe so agent sessions attach to managed launchd Chromes instead of launching Chrome against already-owned profiles, and add a safe cleanup path for stray `chrome://newtab` targets.

## Why
This implements `TASKS.md` P0 `agent-browser-singleton-safe-launch` and traces to:
- Vision goal: `VISION.md` G1 — Self-healing > documented manual steps.
- User story: `docs/user-stories/05-config-heals-itself.md` / US-05 — doctor checks should detect and heal recurring drift.
- Competitor prior art: N/A — this is host-local ProcessSingleton / launchd safety for this dotfiles repo, not a market feature; it aligns with the existing browser-task attach-first rules already deployed in agent instructions.

## Scope (in)
- Add a small dotfiles-owned preflight helper that knows the three managed Chrome profile/port pairs and turns a launchd-owned profile request into either:
  - `exec` attach command output: `agent-browser --cdp <port> ...` when the port is responsive, or
  - a nonzero refusal with a clear message when the profile is singleton-owned but CDP is not responsive.
- Keep the helper as a thin adapter over existing surfaces (`agent-browser --cdp`, Chrome CDP `/json/version`, filesystem `SingletonLock` evidence). It does not launch Chrome and does not replace agent-browser.
- Add a small reap helper that uses Chrome DevTools Protocol `/json/list` + `/json/close/<id>` endpoints to close only page targets with exact blank/newtab URLs on managed ports `9223`, `9224`, and `9225`.
- Extend `modules/agent-browser/doctor.sh` with deterministic checks for:
  - helper scripts exist and are executable,
  - launchd chrome logs contain no `Opening in existing browser session.` lines,
  - managed CDP target inventory contains no blank/newtab page targets when CDP is reachable,
  - repo-managed shell wrapper does not launch against launchd-owned profile dirs.
- Update `home/zshrc.ai-tools` narrowly: preserve the current default-session TCP attach to port `9223`, but add a guard for unsafe `AGENT_BROWSER_PROFILE` values so the wrapper delegates to the preflight helper before invoking `agent-browser`.
- Add Bats coverage for helper behavior and doctor wiring without launching real Chrome.
- Update README/docs claims for the managed CDP ports and attach-first rule.

## Scope (out)
- Do not kill or restart real Chrome/launchd processes.
- Do not mutate the user's live Chrome profiles during tests.
- Do not change public agent-browser upstream code in this task.
- Do not implement the broader `attach-first-browser-policy-wrapper` task. This task only prevents ProcessSingleton launches against launchd-owned profile dirs and removes already-created blank targets.
- Do not use hardcoded task-local debugging ports `9222`-`9225` for new throwaway browser launches. The helpers may hardcode managed ports `9223`/`9224`/`9225` because those are launchd-owned persistent endpoints, not task-local browser ports.
- Do not change the three launchagent plists unless tests reveal their current comments are inaccurate. They already define the managed ports/profile dirs and log paths this task consumes.

## GET-before-IMPLEMENT decision
- GET: Existing Chrome CDP endpoints and `agent-browser --cdp` already provide attach behavior. Use those directly; no browser automation library or custom launcher is needed.
- WRAP: A thin repo-local adapter is still needed because the unsafe input is a shell/user environment shape (`AGENT_BROWSER_PROFILE` or a user-data-dir path) that must be translated to a managed CDP port before agent-browser sees it. A shell function alone would be hard to unit-test and unavailable to doctor; a small `bin/` helper gives zsh and doctor one shared source of truth.
- CONTRIBUTE: No upstream change is required for the local ProcessSingleton guard; upstream contribution is already represented by the separate page-zero/browser policy tasks.
- ABSORB: The only absorbed code is the smallest host-local profile→port mapping and CDP target closer. Add scout follow-up if the helper starts growing beyond mapping + HTTP calls.

## Implementation steps
1. Add failing Bats tests:
   - `tests/agent-browser-singleton-preflight.bats`: fake `$HOME/.agent-browser/*/SingletonLock`, fake `curl /json/version`, assert attach command output vs refusal for each managed profile, and assert unknown profiles pass through without managed-port rewriting.
   - `tests/agent-browser-reap-strays.bats`: fake `curl /json/list` and `/json/close/<id>` responses, assert only exact blank/newtab page targets are closed and real URLs are preserved.
   - Extend `tests/module-agent-browser.bats`: fake log files and fake helper outputs so doctor fails on forwarded-launch lines and stray target inventory.
2. Implement `bin/agent-browser-singleton-preflight`:
   - options: `--profile <path> -- <agent-browser-args...>` and `--print-cdp <path>` for tests/doctor,
   - normalize `~`, `$HOME`, and absolute profile paths,
   - map `chrome-profile`→`9223`, `debug-profile`→`9224`, `tooling-profile`→`9225`,
   - if mapped profile has responsive CDP, print/exec an attach command using `--cdp <port>` and never launch Chrome,
   - if mapped profile has `SingletonLock` but no CDP, exit nonzero with a clear refusal,
   - if profile is not managed, pass through without blocking.
3. Implement `bin/agent-browser-reap-strays`:
   - default ports: `9223 9224 9225`; optional `--port <port>` for tests,
   - list targets via `/json/list`, filter with `jq` to `type == "page"` and URL in `{chrome://newtab/, chrome://newtab, about:blank, ""}` only,
   - close matching IDs via `/json/close/<id>` and print a concise count per port,
   - skip unreachable ports without failing because existing CDP checks own reachability.
4. Extend `modules/agent-browser/doctor.sh`:
   - check helper executables,
   - check each managed log file for zero forwarded-launch lines (threshold: any line is a failure; the task’s incident evidence shows even one forwarded launch means ProcessSingleton was hit),
   - check `agent-browser-reap-strays --dry-run` reports zero closable blank targets on reachable managed ports,
   - keep existing `chrome_cdp`, `debug_chrome_cdp`, and `tooling_cdp` reachability checks as the reachability source of truth.
5. Update `home/zshrc.ai-tools`:
   - leave default-session `--cdp 9223` behavior intact,
   - before `command agent-browser`, if `AGENT_BROWSER_PROFILE` points at a managed profile, call the preflight helper to convert to `--cdp <port>` or refuse,
   - keep `AGENT_BROWSER_NO_AUTO_CDP=1` as the opt-out for automatic CDP attachment but not as an opt-out for unsafe managed-profile launches.
6. Update README/docs:
   - README known caveat line for CDP ports should list persistent managed ports `9223`/`9224`/`9225` and distinguish `9222` as the separate `chrome-debug` LaunchAgent.
   - README LaunchAgents table should include all three persistent managed Chrome labels.
   - README env-var table should document that `AGENT_BROWSER_PROFILE` must not point at launchd-owned profile dirs.
   - Update `docs/module-reference.md`, `docs/security-model.md`, and `docs/what-gets-changed.md` only where they still describe the old two-port/on-demand model.
7. Remove the completed task block from `TASKS.md`, add any concrete scout follow-up discovered during implementation, and verify with focused Bats plus `make check`.

## Risks and mitigations
- Risk: helper accidentally closes real tabs. Mitigation: close only exact blank/newtab URLs and require `type == page`; Bats fixtures include real URL preservation.
- Risk: doctor checks become flaky when Chromes are not running. Mitigation: CDP target checks skip unreachable ports and rely on existing reachability checks to report downed Chromes; log-line checks use deterministic files.
- Risk: wrapper changes break operator default path. Mitigation: preserve existing default-session `--cdp 9223`, preserve `AGENT_BROWSER_NO_AUTO_CDP=1` for auto-CDP, and add tests for unsafe profile refusal.
- Risk: implementation grows into a duplicate agent-browser. Mitigation: helpers never launch Chrome; they only map known profile dirs to managed ports and call existing CDP endpoints.
- Risk: overlap with `attach-first-browser-policy-wrapper`. Mitigation: this task is the safety stop for launchd-owned profile launches; the broader policy task can later choose default port/purpose/session behavior and may reuse these helpers.

## Acceptance criteria
- `make check` passes before commit.
- Focused Bats tests for agent-browser singleton helpers pass.
- Doctor reports a failing check when any forwarded-launch line appears in a launchd Chrome log.
- Doctor reports a failing check when a reachable managed Chrome exposes any exact blank/newtab page target.
- Launch path attaches by converting a launchd-owned profile request to `agent-browser --cdp <port>` when CDP is responsive, or refuses with a clear message when the profile is singleton-owned but CDP is not responsive.
- Reap helper closes stray newtab/blank targets on `9223`/`9224`/`9225` fixtures without touching other tabs.
- README/docs distinguish managed persistent ports `9223`/`9224`/`9225` from separate `chrome-debug` port `9222` and document attach-first / no launchd-owned `AGENT_BROWSER_PROFILE` behavior.

## Reviewer verdict
- **Verdict**: approved
- **Reviewer**: reviewer
- **Date**: 2026-06-11
- **Concerns**:
  - None

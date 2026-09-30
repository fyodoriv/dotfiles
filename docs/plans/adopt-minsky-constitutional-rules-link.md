# Plan: adopt-minsky-constitutional-rules-link

## Goal
Turn the existing `AGENTS.md` / `CLAUDE.md` editing rules into a Minsky-style constitutional rules section that is numbered, anchored, cross-linked to agentbrew where relevant, and explicit about each rule's deterministic gate or advisory status.

## Why
The repo already has strong conventions, but several are terse and not tied to the wider agentbrew/Minsky rule family. The task asks for a durable process map so reviewers can cite concrete rule numbers instead of relying on informal taste, and so dotfiles stays aligned with agentbrew's canonical constitution work.

## Scope (in)
- Update `AGENTS.md` and the synced `CLAUDE.md` copy under `## Rules for Editing`.
- Preserve the current ten dotfiles rules, but add explicit gate/advisory notes and anchors where missing.
- Add at least three new rules requested by the task: hypothesis-driven P0/P1 metadata, proactive healing, and default-by-default behavior.
- Add a `CHANGELOG.md` entry that references the agentbrew sibling task `establish-vision-constitutional-rules`.
- Add a concise architecture cross-reference explaining that the repo-level rules map dotfiles ownership boundaries to agentbrew/Minsky constitutional rules.
- Remove the completed `adopt-minsky-constitutional-rules-link` task block from `TASKS.md` when shipping.

## Scope (out)
- Do not implement new CI scripts for the newly advisory rules in this task.
- Do not modify agentbrew itself.
- Do not rename existing rule numbers in external docs beyond the local `AGENTS.md` / `CLAUDE.md` section.
- Do not change runtime behavior, shell wrappers, doctor checks, or task linting beyond documentation updates.

## Implementation steps
1. Read the existing `AGENTS.md` / `CLAUDE.md` rule list and identify where each rule already has a deterministic gate (`make check`, `make lint-tasks`, Bats, doctor checks, git hooks, chezmoi lifecycle, or explicit advisory-only status).
2. Rewrite the `## Rules for Editing` section in `AGENTS.md` to include a short constitutional framing paragraph, keep rules 0-10, and add rules 11-13.
3. For every numbered rule, include either `**Gate**:` with the relevant command/check or `**Status**: advisory only` with rationale.
4. Add CS / engineering anchors to at least five rules, using existing references where already present and lightweight citations for MAPE-K, GQM, Erlang supervision, and convention-over-configuration.
5. Copy the updated `AGENTS.md` content to `CLAUDE.md` so the two instruction files remain in sync.
6. Add the changelog and architecture cross-reference.
7. Remove the completed task block from `TASKS.md`.
8. Run the measurement command and relevant verification.

## Risks and mitigations
- **Risk:** The rule section becomes too verbose for agent context. **Mitigation:** Keep additions compact and use repeated `Gate` / `Anchor` labels rather than long prose for every rule.
- **Risk:** New advisory rules imply enforcement that does not exist yet. **Mitigation:** Label advisory-only rules explicitly and do not claim CI coverage where none exists.
- **Risk:** `AGENTS.md` and `CLAUDE.md` drift. **Mitigation:** Update both in the same commit and compare them before verification.
- **Risk:** `make lint-tasks` fails because of task formatting changes. **Mitigation:** Remove only the completed task block and keep all remaining task metadata intact.

## Acceptance criteria
- `AGENTS.md` has at least 13 numbered rules in `## Rules for Editing`.
- Each numbered rule has either a CI/lint/doctor/test gate reference or an explicit advisory-only note.
- At least five rules carry CS / engineering anchor citations.
- `CLAUDE.md` mirrors the updated rules.
- `CHANGELOG.md` references agentbrew sibling task `establish-vision-constitutional-rules`.
- `docs/architecture.md` cross-links the constitutional rule map.
- `TASKS.md` no longer contains `adopt-minsky-constitutional-rules-link` after the final implementation commit.
- `make check` passes, or any failure is documented as pre-existing/unrelated with evidence.

## Reviewer verdict
- **Verdict**: approved
- **Reviewer**: reviewer
- **Date**: 2026-06-11
- **Concerns**:
  - Minor: when implementing, make the advisory-vs-gate choice explicit for rules without deterministic checks.
  - Minor: reference rules 11, 12, and 13 directly so the task-requested additions are obvious.
  - Minor: include an explicit `diff AGENTS.md CLAUDE.md` verification check.

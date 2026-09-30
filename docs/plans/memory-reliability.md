# Plan: Local Memory Reliability

- **Repo**: `tooling/dotfiles`
- **Author**: Cursor agent session 2026-08-07
- **Status**: implemented
- **Validated-by**: Cursor reviewer subagent on 2026-08-07

## Goal

Keep the shared local memory service easy to inspect and recover while making
AgentBrew the only runtime owner. Dotfiles declares `memory.enabled`, removes
retired duplicate LaunchAgents, and gates Cursor startup on AgentBrew's
stateful MCP readiness contract. Repository memories must not be treated as
authoritative when their source is stale.

## Why

The memory daemon already provided a local SQLite-vector backend, hybrid search,
consolidation, and a browser dashboard, but the old dotfiles and AgentBrew
surfaces could disagree about daemon ownership and readiness. A port check or a
single `initialize` request could report green while Cursor's MCP host still
had no discoverable tools. Repository memories also needed a deterministic
freshness gate because mcp-memory-service 11.7.0 can expose superseded content
through exact or tag-only recall paths.

## Scope (in)

- Keep `dotfiles memory` as a compatibility shim to `agentbrew memory`; it must
  not start a second daemon.
- Declare memory intent in `Agentfile.yaml` and keep the pre-launch readiness
  gate in `bin/cursor-at-login`.
- Remove or retire dotfiles-owned memory daemon and maintenance LaunchAgents.
- Add doctor checks for AgentBrew readiness and canonical LaunchAgent identity.
- Keep backup and maintenance operations behind AgentBrew.
- Keep the optional dashboard loopback-only and on demand.
- Add revision and source-document fingerprints to `/learn-repos`.
- Reject stale, superseded, or cross-repo retrieval candidates before ranking.
- Add grounded eval scenarios and a 20-question golden set.

## Scope (out)

- Replacing the SQLite-vector backend or embedding model.
- Enabling automatic forgetting or global quality boosting.
- Bulk-rewriting all existing memory records in one run.
- Adding a second memory database, transcript archive, or hosted service.
- Forwarding or remotely exposing the browser dashboard.
- Having dotfiles own `~/.cursor/mcp.json` or `com.agentbrew.*` LaunchAgents.

## GET before IMPLEMENT

- Reuse AgentBrew's pinned upstream `memory` CLI integration for status, schema
  checks, deep checks, dashboard lifecycle, consolidation, and backups.
- Keep AgentBrew's canonical LaunchAgent daemon and MCP registration.
- Use SQLite's `.backup` operation rather than copying the live database/WAL.
- Extend the existing `/learn-repos`, doctor, LaunchAgent, and Bats patterns
  without duplicating the MCP transport probe in dotfiles.

## Implementation steps

### Step 1: Keep the ownership boundary explicit

Keep `Agentfile.yaml` as declarative intent and `dotfiles memory` as a thin
compatibility shim. Document that AgentBrew owns `~/.cursor/mcp.json`, the
canonical memory endpoint, and `com.agentbrew.*` LaunchAgents. Verify the shim
with `bats tests/dotfiles-memory.bats`.

### Step 2: Schedule and observe the owning runtime

Retire the old `com.dotfiles.mcp-memory*` daemon and maintenance artifacts,
make the legacy daemon entrypoint fail rather than launch a duplicate, and
delegate doctor checks to AgentBrew. Verify with
`bats tests/mcp-memory-launchagent.bats tests/module-memory-doctor.bats`.

### Step 3: Enforce source freshness

Require repo path, Git revision, and source fingerprint tags with
`tag_match: all`, reject forbidden recall modes, and backfill incrementally.
Verify with `bats tests/agentbrew-command-sources.bats`.

### Step 4: Add grounded evaluations and documentation

Add stale-revision, fingerprint-drift, supersession, isolation, citation, and
recovery evals plus an inherited-default 20-question golden set. Update
README, architecture, module reference, setup guide, troubleshooting, and
changelog so the AgentBrew/dotfiles ownership and Cursor reload boundary are
consistent. Verify with `make check`.

## Risks and mitigations

- **Risk: backup corruption or WAL inconsistency.**
  - Mitigation: use SQLite `.backup`, verify `PRAGMA integrity_check`, and count
    active memories before accepting a backup.
- **Risk: unauthenticated dashboard exposure.**
  - Mitigation: refuse non-loopback hosts and scope anonymous access to the
    on-demand dashboard process only.
- **Risk: stale memories outrank current evidence.**
  - Mitigation: apply revision and source-fingerprint gates before quality
    ranking and forbid exact/tag-only authoritative recall.
- **Risk: a retired dotfiles job starts a second daemon.**
  - Mitigation: remove retired jobs during apply and make the compatibility
    entrypoint exit non-zero with the AgentBrew repair command.
- **Risk: Cursor retains a stale in-process MCP host after recovery.**
  - Mitigation: report `cursorReloadRecommended` and document **Developer:
    Reload Window** or a full Cursor restart; dotfiles never kills Cursor.

## Acceptance criteria

1. AgentBrew owns the memory lifecycle and the dotfiles compatibility tests pass:
   `bats tests/dotfiles-memory.bats tests/mcp-memory-launchagent.bats`.
2. Doctor checks delegate readiness and detect wrong LaunchAgent identity:
   `bats tests/module-memory-doctor.bats`.
3. Learn-repos command, eval, and golden contracts pass:
   `bats tests/agentbrew-command-sources.bats`.
4. JSON fixtures parse:
   `jq empty commands/evals/learn-repos.evals.json commands/evals/learn-repos.golden.json`.
5. Repository lint and affected tests pass: `make check`.
6. Live apply leaves only the canonical AgentBrew memory runtime loaded, yields
   healthy `agentbrew memory doctor`, a verified backup, and loopback-only
   dashboard access.

## Reviewer verdict

- **Verdict**: approved
- **Reviewer**: Cursor reviewer subagent
- **Date**: 2026-08-07
- **Concerns**:
  - None.
- **Approval rationale** (only if approved):
  - The implementation wraps upstream lifecycle features, keeps the service
    loopback-only, proves backup recovery, and deterministically rejects stale
    repository knowledge. The full local gate and live acceptance checks cover
    the plan's failure modes.

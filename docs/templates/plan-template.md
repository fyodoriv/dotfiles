# Plan: <Title>

<!-- Template for docs/plans/<task-id>.md — copy and fill in.
     Required reading: next-task skill § "Plan and validate".
     Every section heading below is required; sections may be short, but
     must not be omitted. The reviewer subagent will use missing sections
     as concerns. -->

- **Task**: <task-id (matches the `**ID**:` field in TASKS.md)>
- **Repo**: <repo-path>
- **Author**: <agent-id> session <YYYY-MM-DD>
- **Status**: draft | validated | implemented
- **Validated-by**: _(filled in after reviewer subagent run; format: `<reviewer-agent-id> on <YYYY-MM-DD>`)_

## Overall goal and vision

<Start with the operator-facing outcome, why it matters now, the current
constraint or failure mode, and the durable capability this work creates. Do
not begin with files, frameworks, or a proposed implementation.>

## Decision and alternatives

<State the selected direction, material alternatives, and why this choice is
safer, more reusable, or less coupled. Label unresolved choices explicitly.>

## Evidence and current state

| Claim | Current source of truth | How it is provided | Status |
| --- | --- | --- | --- |
| <claim> | <file, API, configuration, or product source> | <runtime path> | fact \| proposed \| verify |

<Keep sourced facts distinct from proposals. Do not infer context from a
similarly named host field or store.>

## Scope (in)

- <Bulleted list of every change this plan covers. Each bullet is concrete and one-commit-sized.>

## Scope (out)

- <Bulleted list of explicitly deferred work, with target follow-up task IDs if known. Anything obviously adjacent to the task that this plan does NOT touch belongs here so reviewers don't suggest adding it.>

## GET before IMPLEMENT

<!-- Prefer wrapping existing tools over writing custom code. List upstream commands,
     doctor checks, catalog entries, or sibling-repo helpers to reuse before adding
     new scripts. If nothing exists, say so and cite the search you ran. -->

- <Existing command / check / upstream to reuse, or "N/A — searched …">

## Boundary contracts (when applicable)

<For a host, embedded surface, API, or state boundary, name the owner,
transport, authoritative source, schema/version, validation, update/reset
behavior, and error/retry UX. Separate Redux store ownership from domain-state
provenance.>

### HostBootstrapPayload (host integration only)

<Define the versioned payload: stable identifiers, host/record context,
capability snapshot, correlation or sequence fields, origin allowlist, schema
validation, and stale/update handling. Explain why it is safer than consuming
the host's private store or passing unbounded URL state. When a provider can
inherit through a sandbox extension or scoped context, document that resolution
path and use named bootstrap actions rather than assume `preloadedState` can
initialize it; treat an explicit store-prop path as a separate contract to
prove.>

## Numbered work breakdown

### 1. <deliverable>

- **Why:** <risk removed or capability enabled>
- **Parallelism:** <parallel with N/M | depends on N>
- **Owner / boundary:** <team or repository>
- **Change:** <smallest concrete deliverable>
- **Evidence / acceptance:** <falsifiable result>
- **Verification:** `<exact command or observable check>`

<Add as many numbered tasks as the work needs. Each task should be one commit
or focused delivery. Name parallel lanes explicitly; do not hide dependencies
inside prose.>

## Risks and mitigations

- **Risk: <name>.** <One-sentence statement of what could go wrong.>
  - Mitigation: <How we'd prevent or detect it.>

<Enumerate at least 3 risks. If the section is empty, the plan hasn't been thought about hard enough.>

## Acceptance criteria

1. <Falsifiable criterion #1, with the exact runnable check that verifies it.>
2. <Criterion #2 + check.>
3. <...>

<Every criterion must have a deterministic verification command.>

## Rollout and regression coverage

- **Merge / deployment order:** <ordered repositories, owners, and feature gates>
- **Security:** <auth, authorization, origin, CSP, sensitive-data handling>
- **Regression coverage:** <unit, contract, integration, and end-to-end checks>
- **Open decisions:** <owner + evidence required to close each one>

## Reviewer verdict

<!-- Filled in by the reviewer subagent. Do not write here by hand unless you are
     the reviewer doing a real validation pass. -->

- **Verdict**: <approved | needs-revision | reject>
- **Reviewer**: <subagent-profile>
- **Date**: <YYYY-MM-DD>
- **Concerns**:
  - <Bulleted list — empty list if approved.>
- **Suggested edits** (only if needs-revision):
  - <Specific changes to make.>
- **Approval rationale** (only if approved):
  - <2-3 sentences confirming why the plan is ready for implementation.>

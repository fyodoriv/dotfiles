# Tooling task audit and delivery plan

## Overall goal and vision

Deliver the unblocked work in Agentbrew and Dotfiles. Keep the declared task
lists and GitHub work truthful, preserve failed experiments, and update each
local default branch after delivery.

## Decision and alternatives

Use each task's acceptance and dependencies to classify it. Do not treat a
missing blocked field as proof that work is ready. Continue existing drafts
before starting duplicate work. A preparation artifact does not satisfy a
separate runtime or live-environment claim.

## Evidence and current state

| Claim | Source | Delivery path | Status |
| --- | --- | --- | --- |
| The task lists are the declared backend. | Each repo's project context loader | Repo task files | fact |
| The compiler receipt checker accepts expected fixture output. | Dotfiles compiler fixture | Offline test fixture | fact |
| An observer meets the sealed decision matrix. | No subject result identified | Future observation boundary | verify |
| Queue metadata is private. | Current queue writers retain raw fields. | Live queue records | verify |

## Boundary contracts

Use synthetic data for measurement. The compiler fixture owns its sealed
inputs and independent receipt oracle; no fixture result proves a live queue
capture. The queue controller owns live records. Do not change live records,
service settings, owner processes, or resource limits during preparation.

## Numbered work breakdown

### 1. Classify open work
- **Why:** Find the next deliverable without losing blocked or in-flight work.
- **Parallelism:** Independent repo audits; precedes new implementation.
- **Owner / boundary:** Agentbrew and Dotfiles task files and PRs.
- **Change:** Compare each task with its source, evidence, and dependencies.
- **Evidence / acceptance:** Every task is actionable, blocked with a reason, or explicitly unknown.
- **Verification:** Read the current task blocks and linked PR states.

### 2. Prepare gate timing attribution
- **Why:** Aggregate step rows cannot establish which phase caused the measured pivot.
- **Parallelism:** After task 1; may proceed alongside the compiler boundary review.
- **Owner / boundary:** Dotfiles gate timing and its existing consumers.
- **Change:** Register and qualify a way to bind step records to the correct invocation, including concurrent runs and the tool-time metric boundary.
- **Evidence / acceptance:** An independent review accepts the frozen controls and exact pre-registered measurement before code; old records and privacy remain safe.
- **Verification:** The reviewed measurement command and the repository gate.

### 3. Collect the agent-hook source slice
- **Why:** The migration inventory needs source-bound evidence for executable entrypoints and embedded interpreter boundaries.
- **Parallelism:** After task 1; independent of the shared validator's delivery.
- **Owner / boundary:** Dotfiles tracked `agent-hooks/` sources at a pinned Git revision.
- **Change:** Land a reproducible receipt registration, then collect and independently review the bounded source slice.
- **Evidence / acceptance:** All tracked paths match the pinned tree; every recorded anchor matches its source; registered planted errors are rejected. The overall inventory remains open.
- **Verification:** The exact command in the landed source-receipt registration, independent source review, and the repository gate.

### 4. Qualify the compiler decision boundary
- **Why:** A receipt checker alone cannot prove correct decisions.
- **Parallelism:** After task 1; independent of other safe task research.
- **Owner / boundary:** Dotfiles test-only compiler observation fixture.
- **Change:** Use the landed test harness, register an independent holdout hash, then evaluate a committed pure decision subject.
- **Evidence / acceptance:** The registered controls and holdout pass without altered inputs or unsafe decisions; live observation remains unclaimed.
- **Verification:** The command in [the decision-model registration](../../plans/compiler-queue-decision-model.md) and independent review.

### 5. Deliver qualified changes
- **Why:** Make proved behavior available and keep local defaults current.
- **Parallelism:** After the relevant experiment and required gate pass.
- **Owner / boundary:** The owning repository and its normal delivery gate.
- **Change:** Ship each reviewed change separately; retain blocked work in its existing draft.
- **Evidence / acceptance:** Required checks and review pass on the exact tree; the merged default is fast-forwarded locally.
- **Verification:** Repo gate, PR state, and local/remote revision comparison.

## Rollout, security, and regression coverage

Preserve frozen cases, closed cohorts, existing queue safety checks and private
data. Do not promote a synthetic result into a live ownership claim. The
Agentbrew full-gate conflict and the compiler capture authority remain open
decisions; each needs an independently reviewed qualification path.

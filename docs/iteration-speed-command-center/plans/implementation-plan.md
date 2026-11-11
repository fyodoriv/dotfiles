# Safe iteration speed implementation plan

## Overall goal and vision

Give each software task a fast feedback loop without weakening its final evidence. Current long gates repeat whole suites, and a demonstrated staged-tree dependency can invalidate a seemingly unchanged result.

## Decision and alternatives

Use the existing rule, performance-review skill, and hook owners. Select affected checks and cache only results whose complete inputs are known. Fall back to the full required check when they are not. Do not force a universal cache implementation or make a timing hint an unconditional block.

## Evidence and current state

| Claim | Source | Delivery path | Status |
| --- | --- | --- | --- |
| The shared instruction template reaches agents | agentbrew `templates/AGENTS.md` | instruction sync | fact |
| Owner-specific rules come from the dotfiles Agentfile | dotfiles `Agentfile.yaml` | apply and agentbrew sync | fact |
| Existing stop-time review measures recurring tool cost | agentbrew `hooks/checks/perf-task-review.sh` | hook sync | fact |
| The standard should act during iterations | user request in this session | shared rules and skill | proposed |
| Any narrower cache key is safe | per-repository test and input census | test gate | verify |

## Boundary contracts

Dotfiles owns the owner rule source; agentbrew owns the deployed instruction template, skills, hook and review guidance. Generated agent config is output only. Hook advice must not change approval, privacy, or full-gate rules. Timing evidence is content-free.

## Numbered work breakdown

### 1. Prove the standard in synthetic fixtures
- **Why:** Missing checks or unsafe cache reuse can hide defects.
- **Parallelism:** First; blocks source implementation.
- **Owner / boundary:** Agentbrew contracts and dotfiles rule tests.
- **Change:** Register the prediction, then exercise the rule, skill, hook, and review guidance in scratch fixtures.
- **Evidence / acceptance:** Every registered positive case passes; missing inputs, failures, and required full gates are never represented as safe cache hits.
- **Verification:** `npx vitest run src/sync/iteration-speed-standard.test.ts` and `bats tests/iteration-speed-standard.bats`.

### 2. Deliver reusable guidance and owner rule
- **Why:** Agents must act before repeated long iterations, not only at session end.
- **Parallelism:** Depends on task 1.
- **Owner / boundary:** Agentbrew sources and dotfiles Agentfile.
- **Change:** Update the existing skill, review/hook guidance, and owner rule. Keep generated mirrors out of commits.
- **Evidence / acceptance:** A scratch sync delivers the rule, and the guidance requires measured iteration feedback plus conservative invalidation.
- **Verification:** `npm run verify:changed` and `make check`, followed by each repo's full required delivery gate.

### 3. Improve the application gate
- **Why:** A cache must not hide an index-sensitive failure, and broad keys repeat costly work.
- **Parallelism:** Cache safety precedes any narrowing.
- **Owner / boundary:** The application gate and its tests.
- **Change:** Bind index-sensitive checks to actual Git state, then measure and qualify smaller targets.
- **Evidence / acceptance:** The synthetic stale-hit case fails before the fix and is caught after it; no narrowing ships without complete input evidence and a measured improvement.
- **Verification:** `uv run pytest tests/unit/test_gate_cache_index.py -q` and the full repository gate.

## Rollout, security, and regression coverage

Merge shared guidance before owner deployment. Use source repositories and their leak gates. Run `agentbrew sync --dry-run` before the approved sync path. Keep all test data synthetic. No rule authorizes skipping required checks.

## Prediction

Goal: put safe iteration speed in the normal development loop. Question: do all registered positive and negative controls reach their intended owner? Metric: the exact tests in task 1. Success: 100% of registered controls pass, with zero unsafe cache or skipped-gate cases. Pivot: abandon the approach if any unsafe reuse or required-gate skip is accepted. Anchor: Basili, Caldiera and Rombach, Goal Question Metric Paradigm (1994).

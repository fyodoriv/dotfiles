# Owner message pending line

## Overall goal and vision

[Issue 439](https://github.com/fyodoriv/dotfiles/issues/439) asks owner-machine
agents to distinguish unfinished work from requests for the user. Add a
`**Pending:**` line immediately before the final `**Needed from you:**` line.
An agent that needs no user action must still show its verified open work.
Keep this personal preference out of a new user's agent configuration.

This is source preparation. No rule, test implementation, generated agent file
or live configuration changed before this prediction was committed.

## Decision and alternatives

Extend `config/agentfile-owner-rules.yaml`. Reuse the existing owner-layer
selection and merged-Agentfile fixture. Do not add a formatter, model runner,
new measurement engine or generic global rule. Agentbrew still owns generated
agent files; dotfiles owns the owner-machine source layer.

Adding this to the base Agentfile would affect other users. Adding only an
ordinary paragraph to a chat would not survive source deployment. A native
hook that rewrites every response would create a new runtime boundary and is
outside this change.

## Evidence and current state

| Claim | Source of truth | Status |
| --- | --- | --- |
| The issue requests Pending before Needed, with live-checked open items and a nothing form. | Issue 439 body and acceptance | fact |
| The owner source has the Needed line and independent ask judge, but no Pending contract. | `config/agentfile-owner-rules.yaml` at base `893097f5b89d795942ce79d436221dfda95decf6` | fact |
| The owner layer is excluded for other users. | `.chezmoiscripts/run_after_agentbrew-sync.sh`, `lib/agentfile-layers.sh` | fact |
| Existing fixtures inspect the actual merged Agentfile for owner and guest identities. | `tests/stranger-readiness.bats`, `_merged_agentfile` | fact |
| Existing rule coverage checks already inspect the owner source. | `tests/agent-artifact-coverage.bats` | fact |
| Extending the owner source exports the new contract without changing other users. | The fixed source/export controls below | proposed |

The source backend is TASKS.md. The issue supplies the requested outcome; this
plan and its task register source work without creating a second issue.

## Scope and boundary contract

- **Owner:** dotfiles' owner-rule source and existing owner-layer selection.
- **Input:** explicit live evidence of unfinished work and required user action.
  Rule tests use synthetic data and generated scratch Agentfiles only.
- **Output contract:** the last two message lines are Pending then Needed.
  Each line independently permits `nothing`.
- **Pending content:** work still running, linked chats/jobs, unfinished cleanup,
  unfinished steps and known follow-ups. Verify each item live before listing
  its current state. Do not infer a current state from memory.
- **Unknown evidence:** a failed live check cannot justify `nothing` or a stale
  status. State that verification remains pending without inventing its result.
- **Preservation:** Needed remains the final line. Its existing independent
  judge requirement for user asks stays unchanged. Other owner rules and
  generic/guest configuration stay unchanged.
- **Lifecycle:** the rule belongs to the owner-machine exported instruction
  layer. Chat facts are invocation-specific and must be checked again for each
  message. This change stores no new chat history or mutable runtime registry.

## Registered hypothesis

**Goal/question:** does the existing owner-layer export carry the Pending
contract while preserving the last-line ask rule and guest exclusion?

**Prediction:** five missing source/export requirements become present: the
canonical Pending contract, ordered owner export, open-work categories,
per-item live verification and independent nothing forms. Their missing count
moves 5 to 0. The guest/base exclusion and existing ask-judge guards retain
their expected decisions. All eight fixed source/export controls pass.

**Measurement:** extend only the existing Bats fixtures with the matrix below
after this prediction commits. The real `_merged_agentfile` route selects the
owner layer in a scratch HOME; its normal agentbrew executable is a fixture
boundary. Run the exact commands below with one inner worker.

**Success:** zero missing owner contracts, all eight fixed decisions correct,
zero owner footer lines in guest/base exports, and unchanged ask-judge and
unrelated-rule content. The required repository gate exits zero.

**Pivot:** any missing owner requirement, guest leakage, changed ask protection,
unrelated rule change or failed gate rejects this approach. A fixture/setup
error is inconclusive. Do not replace the owner selector, weaken the checks or
call a source-text check proof that all model responses comply.

**Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò
et al. (2017), preregistration; issue 439's explicit output contract; the
existing owner-only layer contract in [agentbrew setup](../agentbrew-setup.md).

## Frozen source/export controls

| ID | Boundary and expected decision | Predicted unchanged source |
| --- | --- | --- |
| C1 | Canonical owner rules specify a Pending line before the final Needed line. | Missing; fails. |
| C2 | Actual scratch owner merge exports the ordered footer contract. | Missing; fails. |
| C3 | Actual guest merge contains neither personal footer rule. | Correct; passes. |
| C4 | Base Agentfile alone contains neither owner footer rule. | Correct; passes. |
| C5 | Owner export covers running CI/background jobs/linked chats, unfinished steps, cleanup and follow-ups. | Missing Pending coverage; fails. |
| C6 | Owner export requires a fresh live check for each Pending item, rejects memory-only current status, and keeps unavailable verification explicit. | Missing Pending coverage; fails. |
| C7 | Owner export permits Pending=nothing and Needed=nothing independently, so no ask does not imply no work. | Missing Pending coverage; fails. |
| C8 | Existing ask-judge requirement and other owner rules remain present and unchanged. | Correct; passes. |

C1 checks the instruction contract, not a count of repository strings. C2-C7
inspect the effective selection/export produced by the existing fixture. These
checks prove source routing and content only. They do not execute an LLM or
prove universal response compliance. A later qualified deployment/readback is
separate evidence; do not manufacture generated outputs to make it look done.

## Exact commands

From the repository root, after the prediction and before feature edits:

```sh
JOBS=1 heavy-run bats -- tests/agent-artifact-coverage.bats tests/stranger-readiness.bats
```

Use that identical command for semantic red and green. Keep baseline and
candidate exits separate. The full source commit gate is:

```sh
JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

The docs-only registration also uses `JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=`; it must
exit zero before the prediction commit. It runs existing checks, not the
future C1-C8 implementation. No feature result is claimed by that docs gate.

The initial registration invocation stopped before Bats cases because its
single-worker defaults combined `--no-parallelize-across-files` with jobs=1.
Its failed receipt remains preserved. The explicit empty Bats job arguments
above use the existing supported serial gate. This setup correction changes
no C1-C8 input, prediction, metric or acceptance threshold.

## Numbered work and rollout

1. **Register.** Why: freeze the output and ownership criteria before results.
   Owner: this docs task. Change only this plan and TASKS.md. Verification:
   the declared docs gate above must return zero before the docs-only commit.
2. **Add controls.** Depends on registration and root's source authorization.
   Owner: existing Bats fixtures. Add C1-C8 without a new test runner; observe
   semantic missing-contract failures before changing owner rules.
3. **Extend the rule.** Depends on valid red. Owner: the existing owner YAML
   fragment. Add the Pending contract; preserve Needed and its judge check.
   Update the existing setup guide and run identical green plus the supported
   serial `make check BATS_JOBS= TEST_FILE_JOBS=` gate.
4. **Review and deliver.** Owner: root after source review and required gates.
   No source commit, merge or public write is performed by this preparation
   worker. Current instructions and existing agent settings stay unchanged.
5. **Qualify deployment separately.** Owner: root through existing instruction
   owners. Preview the owner-only change, preserve guest/memory/service/native
   settings, and verify the installed instruction fragment. Do not run a broad
   sync or claim live message compliance from source-only Bats output.

## Security and remaining evidence

No credentials, native transcripts, customer payloads or real chat snapshots
belong in fixtures or public text. Use generic work examples and scratch data.
Only source preparation is authorized at this checkpoint. Root must approve
the next source phase before controls or rule edits, and must keep source
contract proof distinct from deployment and observed agent behavior.

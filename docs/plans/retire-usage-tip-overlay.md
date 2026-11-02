# Plan: retire the usage-tips overlay

- **Task**: retire-usage-tip-overlay
- **Repo**: dotfiles
- **Author**: deployment-cutover-audit, 2026-11-02
- **Status**: prediction before source changes or fixture results
- **Validated-by**: root assigned the bounded source retirement on 2026-11-02

## Overall goal and vision

Stop dotfiles from enabling or preserving the retired usage-tips feature.
The user requested removal from agents and actual archival of its tool repo.
This child covers the dotfiles source overlay only. Agentbrew owns producer,
renderer and generated agent changes; root owns deployment and archive.
This follows VISION G1/G3 and preserves ordinary compaction capabilities.

## Decision and alternatives

Remove the retired ID from owner defaults and migrate already-enabled entries
through the existing chezmoi modify template. Merely removing the default is
insufficient because the template preserves previous entries. Do not replace
the machine overlay or use a formatter that rewrites unrelated content.

## Evidence and current state

| Claim | Source | Delivery | Status |
| --- | --- | --- | --- |
| Owner defaults enable usage-tip | `dot_config/agentbrew/hooks-overlay/modify_manifest.yaml.tmpl:21` at `3955d331` | chezmoi modify script | fact |
| Existing input lines are preserved | Same template, input loop | Previously enabled hook survives a default-only edit | fact |
| Existing test requires the old default | `tests/agentbrew-hooks-overlay.bats` | Existing render harness | fact |
| Active machine overlay has one enabled ID; Codex matches zero | Read-only matched-field retirement audit | Root's separate operator | observed, not a fixture result |
| Retired tool identity | `fyodoriv/claude-usage-tips`, owner/origin verified | Root's archive step | verified; archive not done by this child |

## Scope (in)

- Register fixtures before the existing necessary-shell template changes.
- Remove usage-tip from the owner default and custom override admission.
- Remove its enabled list entries while preserving unrelated text and opt-outs.
- Document the migration and retain repeat-apply behavior.

## Scope (out)

- Agentbrew source, installed hooks/helpers, live overlays or agent configs.
- GitHub archive, public writes, memory/services and user histories.
- Generic compaction instructions or unrelated hook cleanup.
- A new YAML/credential/process engine or broad formatting change.

## GET before IMPLEMENT

Reuse `tests/agentbrew-hooks-overlay.bats`, chezmoi's template renderer and the
existing POSIX modify script. This is a surgical retirement in a required shell
boundary; no new shell/Python engine or runtime dependency is introduced.

## Boundary contracts

The template consumes one supplied overlay on stdin and emits its successor on
stdout. It never opens live configuration. Retirement applies for owner and
non-owner inputs, and a custom DOTFILES_OVERLAY_HOOKS cannot re-enable the ID.
Preserve disabled lists and unrelated comments, strings, IDs and ordering.
Delete only enabled usage-tip entries. Preserve an inline comment on a removed
entry as a standalone comment. Exact scalar IDs may be plain or single/double
quoted. Simple inline enabled lists must also retire the exact ID; unsupported
ambiguous structure must refuse rather than claim successful retirement.
Repeat rendering is idempotent. User overrides still control every other ID.
No Codex file is opened or changed by the template.

## Supplemental R11 refusal controls

Independent source review found valid YAML forms outside the bounded literal
migration. Register these controls before their first probe. Preserve all
original twenty-two assertions and their results unchanged.

| Variant | Supplied form | Required outcome |
| --- | --- | --- |
| R11-space-key | `enabled :` plus a retired entry | Nonzero exit, no stdout |
| R11-quoted-key | `"enabled":` plus a retired entry | Nonzero exit, no stdout |
| R11-item-anchor | `enabled:` with `- &tip usage-tip` | Nonzero exit, no stdout |
| R11-item-alias | `tip: &tip usage-tip` then `enabled:` with `- *tip` | Nonzero exit, no stdout |
| R11-indented-root | Uniformly indented root mapping including `enabled:` | Nonzero exit, no stdout |

GQM hypothesis: unsafe successful acceptance of these five unsupported forms
drops from predicted 5/5 to 0/5. Success: all five refuse without partial output,
and the unchanged original twenty-two controls still pass. Pivot: any accepted
unsupported form, partial replacement or original positive regression rejects
the guard. Refuse unsupported literal syntax; do not interpret anchors/aliases
or build a general YAML engine. The supported canonical live input remains
eligible; actual deployment is a separate root-owned action.

Measurement: the same registered `heavy-run env JOBS=1 bats
./tests/agentbrew-hooks-overlay.bats`, with the five supplement results labeled
separately from the original cohort, followed by the required gate after the
independent base ignore correction is available. Preserve the pre-guard source
and actual semantic red before implementation. Anchor: source review of YAML
mapping/scalar identity; GQM and the existing fail-closed modify contract.

## Supplemental R12 boundary controls

Register three further source-review cases before probes. Preserve the original
twenty-seven assertions and their sealed evidence unchanged.

| Variant | Supplied form | Fixed required outcome |
| --- | --- | --- |
| R12-indentless-sequence | `enabled:` followed by `- usage-tip` at column zero | Nonzero exit, no stdout |
| R12-flow-root | `{enabled: [usage-tip]}` | Nonzero exit, no stdout |
| R12-hash-in-scalar | Enabled item `- usage-tip#custom` | Nonzero exit, no stdout; never delete it as the retired ID |

The first form is a valid indentless YAML sequence; the second is a valid flow
mapping. In the third, a hash without separating whitespace belongs to the
scalar, so it is not the retired ID. The bounded script will refuse all three
rather than interpret more YAML or risk modifying a distinct user hook.

Hypothesis: unsafe acceptance or transformation falls from predicted three of
three cases to zero. Success: all three refuse with no partial output and all
original twenty-seven assertions still pass. Pivot: any successful unsupported
form, wrong-ID deletion, partial output or original regression rejects the
guard. Use the same registered focused command, retaining the new denominator
separately, then the final required gate after normal base-fix integration.
Anchor: independent source review of YAML sequence/flow/comment boundaries;
GQM and fail-closed ownership. No general YAML engine or live action is added.

## Numbered work breakdown

### 1. Register and reproduce

- **Why:** detect the actual default and preservation paths.
- **Parallelism:** independent of agentbrew producer/renderer work.
- **Owner / boundary:** dotfiles template and its existing render harness.
- **Change:** prediction, then frozen fixture assertions on unchanged source.
- **Evidence / acceptance:** semantic failures show retained/re-enabled IDs.
- **Verification:** focused command below, through the shared queue.

### 2. Retire and validate

- **Why:** prevent both fresh and existing machines from restoring the tool.
- **Parallelism:** after the red; source commits remain root-owned.
- **Owner / boundary:** the same template only, with adjacent docs/tests.
- **Change:** narrow exact-ID migration and skip retired custom override.
- **Evidence / acceptance:** frozen cases pass; unrelated bytes and second apply
  remain stable. Root separately verifies live Codex remains zero.
- **Verification:** focused command, then required `make check`.

## Risks and mitigations

- **Default-only fix:** seed an already-enabled manifest in a separate case.
- **User text loss:** compare complete expected output for comments/other IDs.
- **Override resurrection:** explicitly request retired ID through the test env.
- **YAML ambiguity:** test quoting/simple flow; refuse unsupported shapes rather
  than silently emit an enabled retired hook.
- **False live claim:** this harness writes scratch files only; deployment,
  native verification and actual archive belong to root.

## Acceptance criteria

GQM hypothesis: current default and already-enabled retirement violations each
move from predicted 1 to 0. Every fixed fixture decision matches its oracle;
unrelated content changes and second-apply changes are zero. Success: all frozen
cases and required gates pass. Pivot: any re-enabled/retained ID, lost unrelated
line, altered disabled choice or non-idempotent output rejects the migration.
Anchors: user retirement request; Basili/Caldiera/Rombach 1994 GQM;
Munafò et al. 2017 pre-registration; existing modify-script ownership contract.

| ID | Synthetic input | Required result |
| --- | --- | --- |
| R01 | Empty owner defaults | No usage-tip; unrelated owner hooks still enabled |
| R02 | Existing enabled block | Retired entry removed; every other line unchanged |
| R03 | Plain/single/double quoted enabled IDs | Exact retired IDs removed; distinct IDs preserved |
| R04 | Inline comment on retired entry, other comments mentioning the ID | Inline comment retained; unrelated comment lines unchanged |
| R05 | Disabled usage-tip and unrelated disabled hooks | Existing opt-outs preserved byte-for-byte |
| R06 | Custom override includes retired plus valid hook | Retired ID cannot return; valid custom hook still works |
| R07 | Similar names and strings in other sections | No substring-based deletion or unrelated rewrite |
| R08 | Second apply to the migrated output | Byte-identical output |
| R09 | Non-owner with already-enabled entry | Same retirement, no new owner-only hooks |
| R10 | Simple inline enabled list and ambiguous structure | Retire supported exact flow IDs; refuse ambiguous unsupported form |

Freeze actual case variants and expected outputs before the first run. Preserve
old positive assertions unless they explicitly require the retired default;
replace that old requirement with the new negative user contract. No native
transcript, tip log or credential input is permitted.

```sh
heavy-run env JOBS=1 bats ./tests/agentbrew-hooks-overlay.bats
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

## Rollout and regression coverage

- **Merge / deployment order:** source prediction, red/green, required gate,
  root-owned source delivery, then root's reviewed targeted live retirement.
- **Security:** scratch input/output only; unrelated agent config and services
  unchanged; no global bypass or live `chezmoi apply` from this worktree.
- **Regression coverage:** existing render cases plus R01–R10; no source result
  counts as installed or archived proof.
- **Open decisions:** root verifies the installed hook/helper removal and actual
  remote archive; this child must not claim those steps completed.

## Reviewer verdict

- **Verdict**: approved bounded preparation/source task by root assignment.
- **Reviewer**: root, 2026-11-02.
- **Concerns**: final source/frozen results still need root review before commit.
- **Approval rationale**: the existing source/harness can retire the precise ID
  without a live configuration action or another implementation engine.

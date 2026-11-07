# Gate timing attribution: synthetic preparation

## Question and boundary

The seven-day review exceeded the registered pivot for `make check`. The local
step timings cannot yet be joined to those calls. This experiment asks whether
a proposed explicit receipt can bind a synthetic tool completion to exactly
one gate invocation and its step rows, without guessing from timestamps.

This is a local test harness, not a change to the installed gate or agent hooks.
It cannot prove that a real agent supplies a receipt, that output survives
truncation, or that queue wait is included in gate timing. Unknown, truncated,
incomplete, ambiguous, and unpaired calls must remain unattributed. The
existing timing and privacy behavior stays unchanged.

The proposed protocol uses opaque synthetic session, invocation and tool-call
IDs. One invocation record identifies a gate run; any number of step rows refer
to it by session and invocation ID. A synthetic completion carries one receipt
with those IDs. A match needs one completion for one invocation in the same
session, distinct tool-call and invocation identities, and exactly one row per
expected step. Success requires `lint`, `lint-tasks`, `test`, `plugins-bash32`,
`e2e` and `total`, all with status 0. The registered failing control has only
`lint` and `total`, each status 2. Other shapes are unknown in this experiment.
A repeated invocation record is a duplicate; its step rows are not. Treat
IDs as opaque data, never as paths or command text. The test harness supplies
all inputs. It writes a bounded result containing only fixture identifiers,
match or unknown, and fixed reason codes. It does not print raw input, command
arguments, paths, project names, or prompt text.

## Prediction

Goal: establish a safe synthetic baseline before changing production timing.
Question: can a receipt join six valid calls and refuse eight unsafe inputs?
Predict **6/6** valid calls attributed to their correct steps, **8/8** unsafe
inputs marked unknown, **0** incorrect or guessed links, and **0** synthetic
private markers in output or diagnostics.

The valid controls cover a successful call, a failed gate with consistent
status, two overlapping calls, reordered step records, and a nested unrelated
tool call. The eight separate negative controls cover a missing receipt,
truncated receipt, duplicate completion, duplicate invocation ID, missing step,
conflicting status, cross-session replay, and a malformed receipt. Both overlap
and nesting must preserve the true match; times are never used as identity.

## Measurement and decision

After this registration lands, add the proposed test harness and fixtures.
The deliberately unimplemented join must fail the named first valid control.
The red control succeeds only when Bats exits 1 and emits the exact fixed
failure line shown below. A missing test, compilation failure, or other setup
error is inconclusive.

```sh
bash <<'BASH'
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
heavy-run bats --filter '^valid_success$' tests/gate-attribution.bats >"$log" 2>&1
status=$?
[ "$status" -eq 1 ] && grep -Fxq 'not ok 1 valid_success' "$log" && grep -Fq 'synthetic join rejected: unimplemented' "$log"
BASH
```

Then implement the join. The measurement below requires exactly fourteen
individually named tests and a passing repository gate. Each test checks the
exact link or fixed unknown reason, input accounting and marker absence.

```sh
bash <<'BASH'
set -o pipefail
log=$(mktemp) || exit 2
trap 'rm -f "$log"' EXIT
test -f tests/gate-attribution.bats || exit 2
heavy-run bats tests/gate-attribution.bats 2>&1 | tee "$log" || exit 1
grep -Fxq '1..14' "$log" || exit 2
names='valid_success valid_failure valid_overlap_a valid_overlap_b valid_reordered valid_nested unknown_missing unknown_truncated unknown_duplicate_completion unknown_duplicate_invocation unknown_missing_step unknown_status unknown_replay unknown_malformed'
i=0
for name in $names; do
  i=$((i + 1))
  grep -Fxq "ok $i $name" "$log" || exit 2
done
heavy-run make check
BASH
```

Success requires all fourteen controls, no guessed link or disclosure, and a
zero exit from the full gate. Any wrong link, guessed or missing outcome,
private marker, or valid refusal rejects the proposed receipt join; keep the
failing evidence and redesign it instead of changing the controls to obtain a
pass. A missing test or test setup is not a result.

A later, separately registered real-agent experiment must prove receipt delivery
and scope, including failures and truncation, before any observed call can be
attributed. No synthetic result establishes the cause of the seven-day review
or meets the task's speed threshold.

Anchors: Basili, Caldiera and Rombach (1994), Goal Question Metric; Forsgren,
Humble and Kim (2018), delivery performance; the existing Agentbrew perf-row
contract in `docs/agent-perf.md` and Dotfiles `scripts/gate-timed.sh`.

## Synthetic result

The test-only join matched all six valid calls and refused all eight registered
unsafe inputs. The controls also check exact step links, every invocation and
completion, and fixed output. This is a fixture-specific in-memory model, not
a malformed-packet-safe API. It does not check a real completion status,
receipt transport, untrusted output, or actual timing rows. Caller-supplied IDs
can be echoed, so a future contract must prove that IDs are independently
generated and non-sensitive. It does not
attribute any real `make check` call or identify the cause of the seven-day
result. The next step is a separately registered real-agent receipt experiment.

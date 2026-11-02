# Pre-push history pipe registration proposal

Source-bound registration before fixture or behavior changes.
Keep this work separate from the dependency candidate and its failed gate.

## Overall goal and decision

Preserve the public-push privacy check when a pushed commit has a large diff,
file list or message. Reuse `tests/pre-push.bats` and its synthetic repositories.
Do not add a measurement engine or read the owner's private pattern.

The selected experiment tests the actual hook with a synthetic marker and a
clean pushed tip. A shell-only producer/consumer demonstration would show pipe
behavior, but would not establish that the real history gate can permit a push.

## Evidence and current state

| Claim | Source of truth | Status |
| --- | --- | --- |
| The hook uses `errexit`, `nounset` and `pipefail`. | `git-hooks/pre-push:22` | fact |
| Three history branches put `grep -q` after Git producers inside an OR condition. | `git-hooks/pre-push:230-240` | fact |
| Early consumer exit could give a producer SIGPIPE and make a matching pipeline nonzero. | The proposed real-hook counterexample | proposed |
| Existing small history fixtures cover added lines later removed, removed filenames and matching messages. | `tests/pre-push.bats:350-362,419-445` | fact |
| The current file has 37 declared Bats tests; no result was collected for this proposal. | Exact source count | fact |

Reviewed source checkout HEAD: `3955d3317bf05ea907741b6eb635027cf9c42f22`.
Hook SHA-256: `1b0dd81449f7627c7e9e08d1445929ea8587c003cb01814c7402bac896a8cbba`.
Existing test SHA-256: `d66b29864aecc15f2f7ec43b199ef1f0f7f03cf2d4418f200e250ecc59385b5d`.
Recheck these inputs when registering; any source drift needs review first.

## Registered hypothesis

**Goal/question:** can early-match pipe termination make the real hook permit a
history-only synthetic reference when the pushed tip is clean?
**Prediction:** source review predicts three large-stream negative controls expose three unsafe
permits in the unchanged hook. A bounded fully consuming match check reduces
the observed unsafe permits to zero, while all three matching clean controls
and every retained test keep their expected decisions.
**Measurement:** the exact Bats command below; the six frozen controls below
run against the actual hook and existing `_make_repo`, `_pattern_env` and
`_push_range` fixture contract. Record each case, not only aggregate exit.
**Success:** at least one unchanged-hook semantic unsafe permit is observed
before a fix; after the fix all three negative controls block, all three clean
controls pass, and all 37 retained controls pass. Zero marker disclosures.
**Pivot:** if all three negative controls already block, abandon this diagnosis
and do not change the hook. Setup errors and unsupported fixture creation are
inconclusive. Any false permit, clean false block, marker disclosure or retained
regression after a fix rejects that approach; do not change the denominator.
**Anchor:** Bash manual, The Set Builtin (`pipefail`); GNU grep manual, Exit
Status and `--quiet` early exit; Basili et al. (1994), GQM.

## Frozen six-case matrix

All data is synthetic. The marker is `zz-history-fixture-match`; the clean twin
uses the same-length `zz-history-fixture-clean`. The configured pattern is only
the synthetic match string. Fixtures use public test identities and existing
scratch hook isolation. They never push, fetch or contact a remote.

| ID | Producer isolated | Planted fixture and preconditions | Expected |
| --- | --- | --- | --- |
| H01 | Added lines (`git show`) | Commit a text file whose first line is the marker, then 65,536 clean 63-character lines; second commit replaces it with `clean`. Clean names and messages. | Block history-only reference. |
| H02 | Changed filenames (`git show --name-only`) | Commit 4,096 empty files in byte-sort order; first filename contains the marker, following names are 120 ASCII characters with unique numeric prefixes; second commit removes them all. Clean messages and contents. | Block history-only reference. |
| H03 | Commit message (`git log -1`) | Commit a clean file with message file containing a clean subject, marker on the next body line, then 65,536 clean 63-character lines. Use `git commit -F` so argv size is irrelevant. Add a second clean commit. | Block history-only reference. |
| H04 | Added-lines clean twin | Exact H01 with the clean twin string. | Permit. |
| H05 | Filename clean twin | Exact H02 with the clean twin string. | Permit. |
| H06 | Message clean twin | Exact H03 with the clean twin string. | Permit. |

Each fixture saves its initial commit as remote SHA, supplies a nonzero explicit
range to `_push_range`, and proves the pushed tree has no synthetic match.
Assert the actual large producer output exceeds 262,144 bytes, without printing
it. Each negative expects nonzero hook exit and the existing history diagnostic;
each positive expects zero. All six assert captured hook output lacks the
synthetic marker. Do not make runtime duration or SIGPIPE stderr a success metric.

## Boundary and numbered work

1. **Register.** Root adds this bounded hypothesis to a separate task/plan on a
   suitable clean owned branch. Run its declared docs gate and commit before
   adding fixtures. Independent of the frozen dependency candidate.
2. **Observe baseline.** Add only the six real-hook tests to the existing Bats
   file. Run the exact command below under canonical heavy-run with one worker.
   Expected assertion for a semantic red: block expected, actual hook exit zero.
   A Git/setup/tool error does not authorize the fix.
3. **Fix after valid red.** Root reviews the actual error and the smallest
   fully consuming match alternative. Change only the relevant hook branches;
   preserve private output rules, history limits, identities and chaining.
   No evaluation, response-file read, private pattern logging or hook bypass.
4. **Verify and deliver.** Run the identical focused command, then the required
   repository gate. Update existing privacy documentation in the same change.
   Only fresh passing results authorize normal owned delivery.

Exact focused command, registered before fixtures/results:

```sh
JOBS=1 heavy-run bats tests/pre-push.bats
```

The current expected final count is 43 (37 retained plus six new), with zero
ignored controls. Use the repository's normal approved tool PATH. The pre-push
hook's Homebrew Bash shebang remains the runtime; no Bash 3.2 portability claim
is made. Bats regression code remains eligible for the planned Rust migration;
this reuse is not a necessary-shell exemption.

## Rollout and limits

No live history scan or public push is part of the experiment. No private owner
pattern is read, generated or copied. Keep all raw fixture evidence local and
publish only synthetic counts and safe hook transcripts. Do not broaden the
claim to every Git producer failure, every push range or a universal leak proof.
The earlier broken-pipe observation is only the motivation, not baseline data.

## Test-runner setup correction

The first fixture-only attempt used a standalone `--` before the test path.
The installed Bats rejected it as a bad command-line option and executed zero
tests. That attempt is inconclusive. Before the first valid baseline, correct
only the invocation to `JOBS=1 heavy-run bats tests/pre-push.bats`. The six
registered fixtures, their expected outcomes, the 37 retained controls and the
unchanged hook hash stay fixed. No behavior result informed this correction.

## Observed results

The corrected unchanged-source run executed all 43 controls. Each of the three
large matching streams was wrongly permitted; the other 40 controls passed.
Replacing only the three early-exit matchers with fully consuming matchers
made all 43 pass, including the three clean twins and all 37 retained cases.
The original failed and passing transcripts remain local. Required repository
validation remains a separate delivery gate.

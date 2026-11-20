# Match compiler root evidence to sealed observations

Registration date: 2026-11-20. Target: `8b3d6213`.

The [decision plan](compiler-queue-decision-model.md#qualified-root-evidence-registration)
requires separate root references for the two captures. This change prepares
the fixture join. It does not classify a process or collect live data.

- **Hypothesis**: A harness can bind an independently sealed companion packet to the exact observation bytes, match each case once, and pass the root claims on without guessing missing evidence.
- **Measurement**: On hosted CI, run `bats tests/compiler-root-companion.bats`. Send the 12 registered synthetic case shapes through the join. Check 12 exact projections, including deliberately missing or conflicting root claims. Run the 10 separate intake controls below. Compare the frozen source files and holdout hash with the target.
- **Success**: 12 of 12 synthetic projections match. All 10 invalid inputs produce a fixed refusal, with zero partial results, private output, case IDs or expected verdicts in projected observations. Zero frozen files change.
- **Pivot**: Stop after 1 wrong association, 1 missing or conflicting claim filled in, 1 private value printed, or 1 changed frozen file. Revise the join contract before measuring any decision.
- **Anchor**: The [compiler root protocol](compiler-queue-decision-model.md#qualified-root-evidence-registration), the [original hash registration](compiler-queue-holdout-registration.md), and Basili, Caldiera and Rombach (1994), Goal Question Metric.

## Companion format

The independent reviewer keeps the companion UTF-8 bytes and publishes
their SHA-256 before the new subject is committed. A companion binds itself
to the SHA-256 of one original observation packet. The fixture harness gets
both expected hashes from their checked registrations. A hash confirms exact
bytes. A reviewer must independently verify who supplied each root claim.

An observation packet is the frozen version 2 object with `cases`. Each
case has a unique string `id` and an `observation` object. The companion is
a version 1 object with `observation_sha256` and an `entries` array. Each
entry has exactly `id`, `root_before` and `root_after`. Each of the two
root fields is either null or an object with these fields:

- `boot` and `view`: nonempty synthetic identity strings.
- `pid`: positive integer.
- `birth`: positive integer, matching the frozen process tuple.
- `covers_queue`: Boolean claim that the process view covers its queue lanes.

The join verifies both SHA-256 values before parsing. It requires exactly
one companion entry for each original case. It copies both root fields
to the observation under the same names. An existing name at that location
is a conflict. Null is an explicit missing claim. The join preserves it.
A well-formed mismatch between the two root references must reach the
future subject so the decision controls can verify an unknown result.

The case ID remains only in the harness lookup. A future runner must provide
observations to the subject in a separate, independently chosen order.
The join does not call the subject. Projected observations carry neither
the ID nor the expected verdict. The trusted frozen observation is the source
of nested evidence. This fixture reports counts and fixed
refusal labels without quoting input or decoded payloads.

## Intake controls

The invalid controls start from a passing synthetic pair.
The expected result for each is a refusal before a result can be handed off.

| Control | Input change |
| --- | --- |
| J01 | Malformed original bytes differ from the registered hash |
| J02 | Malformed companion bytes differ from the registered hash. The original digest matches malformed bytes, to check that both digests precede either parse |
| J03 | The sealed companion names the wrong original hash |
| J04 | The original packet has a repeated case ID |
| J05 | The companion has a repeated case ID |
| J06 | The companion omits an original case |
| J07 | The companion adds an unknown case |
| J08 | A root reference has an invalid field type |
| J09 | An observation already contains a destination root field |
| J10 | A companion object has a repeated JSON key |

Use public, synthetic values for these controls. Preserve the old holdout
hash and the 24 of 24 plus 8 of 8 decision thresholds. The join cannot
replace the original eight cases or verify a live root provider.

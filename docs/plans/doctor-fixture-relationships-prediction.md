# Doctor fixture relationship prediction

An exploratory source review found two test fixture module names and a
conditional route through the doctor module loader. This observation predates
this prediction. It does not prove a fixture ran or establish all callers.

Hypothesis: a pinned source check can identify both fixture candidates and
bind each test's fixture-root assignment and module invocation to the doctor
loader's guard, ordered selection and source operation.

Measurement: `python3 docs/plans/doctor-fixture-relationships.py --check` and
its focused mutation controls against the pinned source revision.

Success: both candidates have anchored conditional relationships, all checked
source identities match, and at least four altered identity or anchor controls
are rejected. Pivot: retain any ambiguous or unsupported candidate as
unresolved. In particular, an earlier core module with the same name can win;
loader admission depends on the Bats marker and fixture directory. Do not
infer execution, ownership or complete caller coverage.

Anchor: `docs/plans/rust-source-inventory.md` and the pinned test and doctor
sources listed in the checker receipt.

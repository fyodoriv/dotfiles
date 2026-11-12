# Cold-path fixture safety audit

Registered before the complete source audit on 2026-11-11. The cold-path task
names doctor, apply, sync, upgrade and the shared queue. No local p50 was
available from the registered command log query. A system tracing provider
probe required additional privileges, so no system trace was collected.

Hypothesis: a source audit can identify the scratch-root, external-tool,
network and background-process boundaries for all five proposed fixture
families before timing. This does not claim that the fixtures are safe or that
child time is separable.

Measurement: inspect the selected tests, setup and called source at the pinned
revision. Record one row per family with source paths, known boundaries,
unverified behavior, and a safe next action. Independently review every row.
Do not run a workload, contact a remote service, open an app, or signal a
process during this audit. Compare the table with the five task families.

Success: five of five families have reviewed rows, zero host mutations occur,
and every unknown remains marked unknown. Pivot: any uncovered call, ambiguous
fixture boundary or claimed timing result without measurements keeps that
family unqualified. A later registered experiment must prove scratch isolation,
complete child-span coverage, overlap handling and calibration before reporting
owned wall-time share. If two or more families cannot be separated, apply the
original cold-path task's pivot rather than estimate.

Anchor: `rust-cold-path-profile` and its gate in `rust-migration.md`; Basili,
Caldiera and Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

# Register sync preview file measurement

The runner writes sync status after sequential and parallel previews; the
parallel runner also calls the manifest writer. Failed runs call the event
writer. Existing runner tests mock these writers, so they do not measure the
actual file effects. This is preparation, not a fix.

Goal: make preview file effects measurable without touching user data.
Question: do synthetic sequential and parallel preview runs change seeded
scratch status, manifest or event records? Predict status changes in 4/4
cases, manifest changes in 2/2 parallel cases, and event bytes change in 2/2
failed cases. Success requires all 8 predicted observations and 4/4 real-run
positive controls to be detected with no path escape or unexpected process or
network activity. Any missed observation, failed control, path escape or
unexpected process/network attempt rejects this harness design. Setup failure
is inconclusive and requires a redesigned harness. The follow-on fix needs its
own committed hypothesis and before/after measurements.

After this registration, create a separate test file for the actual runner and
actual persistence modules. Measure with
`JOBS=1 VITEST_MAX_WORKERS=1 heavy-run npx vitest run --maxWorkers=1 src/sync-runner-preview-files.test.ts`.
Before importing the runner or manifest, require the effective HOME, status,
manifest and explicitly enabled event paths to resolve inside the test-owned
scratch root. The manifest path is captured at import. Seed distinct valid
synthetic bytes for each test and compare bytes without printing them. Use
sequential/parallel × success/failure preview cases. Parallel modules mutate a
synthetic manifest field so a real save is observable. Also run matching real
success/failure controls that prove status, manifest and event writers can
change their intended scratch files. Fail closed if paths, the seed or a
positive control cannot be established.

Mock state, Agentfile and project discovery, sync adapters, installs, snapshot,
source refresh, drift and budget reporting before import; pass only synthetic
in-memory modules. Prove no install, subprocess or network path is used with
explicit sentinels. Scope any stronger no-network or process claim to an
operating-system denial if one is actually installed. Restore environment,
cwd, exit code and mocks; wait for all work before removing scratch state.
Require independent review, focused tests, the repository's required full
gate, and a same-PR note that this measures runner-level synthetic behavior,
not every CLI/module side effect or physical installed state.

Anchor: source inspection of `src/sync-runner.ts`, `src/core/errors.ts`,
`src/core/events.ts` and `src/manifest.ts`; Basili, Caldiera and Rombach (1994),
Goal Question Metric; Munafò et al. (2017), preregistration.

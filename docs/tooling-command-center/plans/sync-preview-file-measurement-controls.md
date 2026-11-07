# Freeze preview measurement controls

Supplement commit `4f4d56b` before implementing its scratch-file harness.

Name eight preview observations exactly: `S_OK_STATUS`, `S_FAIL_STATUS`,
`P_OK_STATUS`, `P_FAIL_STATUS`, `P_OK_MANIFEST`, `P_FAIL_MANIFEST`,
`S_FAIL_EVENT`, and `P_FAIL_EVENT`. `S` means sequential and `P` means
parallel. Name four real-run controls `REAL_S_OK`, `REAL_S_FAIL`, `REAL_P_OK`,
and `REAL_P_FAIL`. The real-run controls each require a status write. Both
failed real controls require an event append. Both parallel real controls
require a manifest mutation and save. Do not require sequential manifest
writes or successful event appends.

The named-test command is the focused Vitest command in `4f4d56b`. It must
machine-check exactly eight individually named preview observations and four
individually named real controls, with no missing, duplicate, skipped or TODO
case. The seeded status is valid and has a fixed timestamp that cannot equal
the run timestamp; seed and validate all three synthetic records before each
case. Require real controls to prove actual scratch writes because persistence
errors can be swallowed. Verify synthetic module and isolation mocks are in
place before importing the runner and prove no project Agentfile executes.

Subprocess and network sentinels only prove the instrumented APIs. Claim
operating-system-wide denial only if a separate denial is installed and
verified. The success, pivot, exact command and literature anchors remain those
in `4f4d56b`.

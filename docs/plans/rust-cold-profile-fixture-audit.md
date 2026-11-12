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

## Source audit at `70a704e`

These are fixture candidates, not approved workloads. No timing or workload ran
in this audit. Each next action applies before any later measurement.

| Family | Source boundaries | Still unverified | Next action |
| --- | --- | --- | --- |
| Doctor | `tests/doctor-validate-overrides.bats` creates a scratch HOME, copies doctor and its helpers, and puts a fixture `chezmoi` first on PATH. `bin/dotfiles-doctor` still invokes other tools. | Complete external-child coverage and background work for the selected command. The fixture covers a fake module, not every doctor module. | Audit the selected command's full call tree and deny host or network access in a scratch runner. |
| Apply | `tests/dotfiles-apply-if-changed.bats` copies the entrypoint and helpers into a scratch repo, stubs doctor and chezmoi, and uses a scratch HOME. It disables the global Git config in its setup. | System Git configuration, hook routing, all child calls and span coverage are not established by the fixture alone. | Isolate system config and hooks, deny nonlocal operations, and account for every child before timing. |
| Sync | `tests/dotfiles-sync.bats` builds a local bare remote and copies repos per test. Its file-level setup performs Git operations before the per-test HOME is set; `bin/dotfiles-sync` can start a background reload helper. | Inherited Git configuration and hooks during setup, background coverage, and the absence of nonlocal calls in a selected path. | Move all setup into a verified scratch environment, restrict the remote to the fixture, and observe or exclude background work. |
| Upgrade | `tests/dotfiles-upgrade.bats` uses a scratch HOME and stubs topgrade, process lookup and notifications, but sets `DOTFILES_DIR` to the source checkout. `bin/dotfiles-upgrade` contains calls to executable helpers under that directory. | Whether a selected run reaches those helpers, and whether any helper writes outside the scratch root or starts an unobserved child. | Copy or replace all reachable helpers in a scratch checkout and deny host changes before running it. |
| Queue | `tests/heavy-run.bats` assigns a private `HEAVY_RUN_DIR`, scratch HOME and test-owned holder. Its teardown checks job ownership before signaling. | Complete child-span coverage, overlap accounting and calibration for a chosen queue workload; the fixture does not describe the live queue. | Use only owned fixture identities and a private queue; validate span coverage and never signal live sessions. |

All five rows remain unqualified for owned-time attribution. The Git, network
and tool categories cannot be split merely by timing a parent that can spawn
helpers. No missing span is treated as zero. Local p50 remains unknown until
valid matching command-log samples exist.

The reviewer checked the five source rows against the pinned tree. The
content-free command-log count had no matching rows for the five families.
The local provider probe `/usr/sbin/dtrace -l -P syscall` exited 1 and reported
that additional privileges were required; it did not collect a trace. These are
session observations, not independently reproduced workload measurements.

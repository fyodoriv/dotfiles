# Support contracts for contributor PRs 410 and 414

## Goal and scope

Prepare the shared base so the original contributor PRs can merge directly.
Keep their production changes in their original PRs. This support branch
does not absorb those changes or close their issues.

The base needs two narrow corrections: a full-profile IDE fixture must create
the app whose checks it expects, and check-ID discovery must set list mode
while it sources optional modules. The second correction keeps an opted-out
module's IDs valid for skip and override validation.

## Existing predictions

Commit `267ded5` registered the IDE fixture correction before implementation.
Its combined three-file measurement also includes the Claude fixture and
export scanner. This branch adopts only the IDE fixture slice. PR 431 already
delivered the Claude fixture; this support branch does not claim the combined
measurement or deliver the scanner.

Commit `f60a71f` registered doctor correctness before implementation. Its
hypothesis reduces rejected valid opted-out IDs from one to zero, with zero
failures across its named suites. The new planted controls exercise that
same known ID through both CLI entrypoints. Their fixture uses a 414-style
opt-out guard; it does not copy contributor production code into this base.

## Registered support measurement

- **Hypothesis**: setting list mode only during check-ID collection reduces
  rejection of the planted valid ID from one to zero through both skip and
  override validation. Creating the expected GoLand app keeps the IDE fixture
  valid before and after installed-app-only behavior lands in PR 410.
- **Measurement**: first run the two discovery controls below on the unchanged
  CLI and inspect their actual results. Then apply only the collector's local
  list-mode flag and the previously registered IDE fixture correction. Run the
  same frozen controls, both affected suites and the required full gate.
- **Success**: the valid ID is accepted by both entrypoints; neither executes
  its synthetic audit predicate; both affected suites and the required full
  gate pass. The IDE fixture creates GoLand and retains all base assertions.
  Existing unknown-ID refusal remains intact. Installed-app-only absence
  behavior belongs to original PR 410 and its own controls.
- **Pivot**: any rejected valid ID, executed audit predicate, unknown-ID
  acceptance or affected-suite regression rejects the collector change.
  Diagnose the discovery boundary rather than weakening a fixture or changing
  the contributor's opt-out behavior.
- **Anchor**: Basili, Caldiera and Rombach (1994), Goal Question Metric;
  the pre-registered `267ded5` and `f60a71f` contracts.

```sh
heavy-run bats --filter 'discovery mode:' tests/doctor-validate-overrides.bats
heavy-run bats tests/doctor-validate-overrides.bats tests/doctor-core-profile.bats
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

The initial preparation staged only this plan and the two discovery controls,
with the collector CLI unchanged. That baseline exited one: the skip control
passed, while override validation rejected the valid ID with status one at
its expected-zero assertion. This is one semantic failure and one positive
control, not two failures. It matches the original valid-ID rejection
prediction. Both controls and all unknown-ID negatives remain unchanged.
The next candidate applies the one-line collector fix and registered IDE
fixture correction. Its focused run passed both discovery controls and all
unknown-ID controls. It failed only the newly added WebStorm-absence assertion
in the profile fixture: that expectation requires PR 410's production change.
The base did not contain this assertion. Omit that premature new expectation
from the support base, while preserving every base assertion and the GoLand
setup. The broad follow-up retains the absence assertion, and original PR
410 independently tests settings-without-app behavior on both profiles.
This is delivery sequencing; no original coverage or success threshold is
removed. No full-gate success or installed-app-only delivery is claimed here.

The subsequent full gate stopped only at the existing literal-Perl alarm
guard: the current base's two heavy-run fixture holders armed their safety
alarms without resetting inherited SIGALRM handling. Adopt the exact two
reset lines already registered by `9ed2c71` and `a7165ba` and preserved in the
broader reviewed composition. Keep each 60-second safety bound, every
assertion and production queue behavior unchanged. This reuses the registered
fixture correction; it is not a new production change or a gate waiver.

## Implementation boundary

Use one dynamically scoped `LIST_MODE=true` local within
`collect_known_check_ids`. It lasts only for that discovery call. Do not change
normal audit mode, override storage, plugin dispatch or repair handling.

For the IDE fixture, create only its expected scratch GoLand app and retain
every base assertion. Defer the new WebStorm-absence assertion until the
installed-app-only production behavior lands in PR 410. Do not change
production IDE discovery here.
Update the relevant doctor/fixture documentation in the same delivery.

After the support base passes its gates and merges, validate and normally
merge original PR 410, then original PR 414, against their exact current
trees. Preserve all remaining broad owned work. A support-only result does
not complete the broader doctor correctness or three-file contract task.

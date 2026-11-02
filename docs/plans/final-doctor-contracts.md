# Final doctor contract corrections

Prediction committed in 267ded5 before the corrective fixtures or scanner.
The initial final-gate logs identified these three target files. Their frozen source
was copied into an isolated checkout; the running gate source was not
changed.

## Classification

- Claude expectations were stale on the unchanged default base: seven
  registered checks include `claude.mods`, while the test expected six.
  The contributor change only edits the mods description. Pin all seven
  IDs and keep exact pass/fail totals.
- Installed-IDE-only behavior makes an old full-profile fixture invalid:
  it creates settings folders without the GoLand app. Create only the
  expected GoLand app and assert WebStorm stays absent.
- The export guard treated the last quoted predicate line as a repair.
  The GitHub helpers are third arguments on report-only checks, so they
  run in the module process. Do not export the auth snapshot or helpers.
  Parse actual call argument positions and preserve genuine fourth-argument
  repair detection with planted controls.
  A review seed first reproduced a dynamic-suffix false positive. Preserve
  prefix completeness: `helper` plus an unknown command suffix stays
  unknown, while `helper` followed by an argument separator remains a
  known helper call even when its arguments are dynamic.

## Scope of this delivery

PR #431 delivered only the Claude fixture correction. This follow-up also
adopts the IDE fixture and export scanner from the same original prediction.
Run all three files and their planted controls before merging; a Claude-only
receipt does not complete this measurement.

## Measurement

Run `heavy-run bats tests/module-claude.bats tests/doctor-core-profile.bats tests/doctor-fix-functions-exported.bats`.
Keep the changes only when all three files pass and every planted
predicate, missing-repair, exported-repair, and advisory control has the
expected result. Any failure abandons this shortcut until the actual
contract is understood. The final combined source still needs its required
`heavy-run make check` gate before a source commit.

Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric; Forsgren,
Humble, Kim (2018), stability; `bin/dotfiles-doctor` check argument contract.

# Learnings

Every non-trivial change states a prediction before the work (rule 11). This
log records what was predicted and what was observed, so the next prediction
is better calibrated. It is append-only: add a row when a change merges; never
rewrite an old row. The monthly checkup reads it next to
[metrics.md](metrics.md).

| Date | Change | Predicted | Observed | Kept? | Lesson |
|---|---|---|---|---|---|
| 2026-10-16 | Fix two failing doc tests; trim AGENTS.md (#124) | 2 failing tests pass; no other change | Both passed, but the trim dropped two phrases `agent-artifact-coverage.bats` requires; the gate never ran that test | Yes, fixed in #127 | `bats-affected` must select tests that read a changed file by path (fixed in the speed-review PR) |
| 2026-10-16 | Metrics with goal, pivot, command (#125) | check-setup 11/24 → 14/23 | 14/23 | Yes | A metric source that answers 0 for missing data needs `pipefail` and an explicit error, or the table shows a fake 0 |
| 2026-10-16 | One-line setup, story metrics, story e2e (#126) | check-setup 14/23 → 16/23; all story e2e green | 16/23; 16 e2e green after fixing 2 `morning` bugs the e2e found | Yes | A hermetic e2e of the real command finds bugs unit tests with stubs miss (`set -e` on an empty repo, a missing `ps`) |
| 2026-10-16 | Errors log; a fix on every doctor failure (#127) | check-setup 16/23 → 17/23 | 17/23 | Yes | Adding a lib to a sourced script breaks every test fixture that copies libs one by one; grep for the copy lists first |
| 2026-10-16 | ADRs, `.env` ignore, rule 9 scope (#128) | check-setup 17/23 → 18/21 | 18/21 | Yes | Check the default path (`bin/add-task` defaults to P2) before tightening a lint on it |
| 2026-10-16 | Timed gate, cache-key fixes, learnings (#129) | check-setup 18/21 → 19/19; both cache tests red then green | 19/19; both red then green; an AGENTS.md edit now selects agent-artifact-coverage.bats | Yes | A cache test that changes the command proves nothing; the command is part of the key |
| 2026-10-16 | Grader fixes (#130) | the fresh grader's 6 intent FAILs (metrics, stats allow-list, setup re-run, tasks, secrets wording, map comments) all PASS | the 6 passed; the re-grade found 3 new FAILs (hard-coded bootstrap count, setup stops on a missing tool, checkup P0 wording) | Yes, follow-up #131 | A scorer that only checks that mapped files exist reaches 100% before the intent does; grade by intent before claiming done |
| 2026-10-16 | Re-grade fixes (#131) | the 3 re-grade FAILs pass; fresh-Mac commands 4 → 1 (measured from the README) | all 3 passed; steps 1 (measured); the final grade found 1 map claim (a render test listed as e2e), fixed in #132 | Yes | Bats files that call the real doctor without test_helper wrote failing runs into the real stats log and pushed the US05 doctor rate from 93% to 70%, past its pivot; logs now stay off under bats by default |
| 2026-10-16 | Confirmation-grade fixes (#133) | the 4 FAILs pass (real 0 vs stub, quiet-line fix, fixture-aware test selection, map comments) | all 4 passed; the next grade found test selection blind to tests/plugin and to libs the e2e commands load | Yes, follow-up #134 | Each fresh grader reads deeper than the last; give the final grader the exact rule list and fix every FAIL before calling it done |
| 2026-10-16 | Selection depth (#134) | subfolder tests and e2e libs selected; tests/plugin runs in test-all | both selected; the next grade found `--validate-overrides` failure lines without a fix | Yes, follow-up #135 | Derive triggers from what a command loads instead of listing paths by hand |
| 2026-10-16 | Overrides fix lines (#135) | every doctor failure line, `--validate-overrides` included, carries a fix | yes; the next grade found the e2e trigger blind to libs the doctor modules and lifecycle scripts load | Yes, follow-up #136 | A lint that greps one call shape (`fail "`) misses other failure output; test the command's real output |
| 2026-10-16 | e2e trigger scan (#136) | libs from modules and lifecycle scripts trigger the e2e | yes; the next grade found selection blind to tests that use their own repo-root variable | Yes, follow-up #137 | Scan everything a test runs, not only its entry commands |
| 2026-10-16 | Root variables in selection (#137) | tests reading a file through any variable set from BATS_TEST_DIRNAME/FILENAME are selected | yes; the next grade found fixture files read through their folder missed | Yes, follow-up #138 | Learn each test file's own root variables instead of a fixed name list |
| 2026-10-16 | Fixture folders (#138) | a file inside a fixture tree selects tests that read any parent folder | yes; the next grade found lock-failure lines without a fix | Yes, follow-up #139 | A test reads a folder as often as a file |
| 2026-10-16 | Lock and error fix lines (#139) | every doctor failure line, including lock and argument errors, carries a fix | pending the next grade | — | Guard the output a user sees, not one call shape |

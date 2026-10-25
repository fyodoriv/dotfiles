# Monthly repo health, stories, and gate speed review

Part of tooling-checkup Phase 7, once a month.

In the same monthly pass, for `dotfiles` (run from its checkout):

1. Health: `bin/dotfiles-doctor --quiet`. Each failing check line names its fix.
2. Cached gate: `make check`. `bin/cached-run` skips unchanged steps;
   `make test-force` runs everything.
3. Broken stories: `make e2e`. A failing test name starts with its story ID
   (`USNN e2e: …`); report the story, not only the test.
4. Speed review: `bin/dotfiles-metrics --table`. Compare the `make check`
   row (from `~/.local/state/dotfiles/gate-timings.jsonl`) and every other
   metric with its goal and pivot. Per-step times:
   `jq -s 'group_by(.step) | map({step: .[0].step, median: (map(.seconds) | sort | .[length/2|floor])})' ~/.local/state/dotfiles/gate-timings.jsonl`.
   A metric past its pivot becomes a P0 or P1 task with the numbers.
5. Learnings: add a row to `docs/learnings.md` for each prediction closed
   since the last checkup (predicted vs observed).
6. Open P0s: list `## P0` in `TASKS.md`; each one goes to "Next: stability".
7. Changelog: `make changelog` regenerates `CHANGELOG.md` from conventional
   commits (dotfiles has no release tags, so the monthly pass is its
   release). Ship the diff as a `docs(changelog):` PR; never edit it by hand.


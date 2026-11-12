# Hook baseline: November 11, 2026

Before any hook replacement, 20 clean and 20 linked A/A gate runs passed
with zero failures. Both sides used executable source at commit `5c16942`.
The measurement checkout removed only the one-PR gate self-review marker;
the linked set included all 11 local executable links. The merged commit
`57a4b14` has the same hook, endpoint-path helper and `bin/` source.
The saved setup and a post-run check confirmed matching link names and link
texts. They do not prove that no transient external change occurred during
the run; the gate also checks link identity around each sample and target
content before and after the run.

The linked set's `base_min` values below are milliseconds, in run order.
Each value is the fastest of 15 samples for that tree in the gate run. These
are baseline observations, not a new acceptance rule. The retained gate
records contain verdicts and summaries, not all 15 individual samples or a
complete independently reviewed executable and interpreter chain. They do
not establish the full retained-sample and input-provenance contract. The
historical gate used a scratch child environment; it was not the later RSS
startup path.

- `hook-require-heavy-run`: 50.090, 51.242, 56.729, 56.237, 60.386,
  56.382, 51.691, 53.756, 49.436, 52.071, 53.998, 50.028, 49.742,
  53.768, 51.397, 50.200, 56.027, 48.250, 51.399, 51.238. Median: 51.545.
- `hook-block-dangerous-git`: 44.714, 44.626, 52.673, 44.073, 50.454,
  40.750, 50.346, 40.271, 41.447, 48.338, 41.427, 50.134, 39.822,
  41.995, 40.599, 50.933, 47.522, 40.861, 40.593, 47.795. Median: 44.3495.

The existing [migration plan](rust-migration.md#measurement-contract) keeps
its 0.50 benefit ratio, resource and parity gates. No hook was ported in
this measurement.

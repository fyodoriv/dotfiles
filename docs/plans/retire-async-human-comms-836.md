# Retire the unused communication hook

Issue: #836. The owner overlay enables `async-human-comms-blocks` before
every tool call. Its unused file convention can add a timeout to each call.

Hypothesis: retiring this hook from fresh and existing per-machine enabled
lists removes its tool-call delay while preserving other hook choices.

Measurement: hosted `tests/agentbrew-hooks-overlay.bats` checks fresh defaults,
existing block and inline lists, quoted IDs, disabled choices, custom overrides,
and repeat application. After deployment, inspect the installed hook list.

Success: zero enabled occurrences of the retired ID in every registered case;
zero changes to disabled choices or unrelated IDs; required CI is green.

Pivot: any retained retired entry or changed unrelated choice rejects the
migration. Keep the existing parser and fix its exact-ID handling.

Anchor: issue #836's recorded timeout observations and the existing usage-tip
retirement contract in `tests/agentbrew-hooks-overlay.bats`.

The per-machine overlay remains the owner of mutable hook selections. This
change removes the retired ID only from enabled selections. It does not delete
the hook source or change another machine's disabled choices.

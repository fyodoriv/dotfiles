# Freeze non-signaling ownership controls

Supplement `3bb4fd0` before implementing the synthetic model. Preserve its
seven named cases and add `DUPLICATE_TIMEOUT`, `FRESH_TOKEN`,
`INVALID_CLOCK`, and `UNKNOWN_STATE`: exactly 11 cases.

`DUPLICATE_TIMEOUT` calls twice after the deadline for the same synthetic
ownership token and expects exactly one recorded action and unchanged result.
`FRESH_TOKEN` proves a different verified token can independently request an
action. `INVALID_CLOCK` checks NaN, infinity, missing values and a clock moving
backwards; all fail closed. `UNKNOWN_STATE` checks missing and non-boolean
ownership/liveness and missing or mismatched identities; all fail closed.
`SIGNAL_FAILURE` distinguishes a failed fake action from an unknown final
child state and reports the outcome as unqualified.

The model under test starts no subprocess and invokes no real signal or
`process.kill`; the scheduler and Node test runner themselves are processes.
Source review must verify that boundary. The command in `3bb4fd0` must exit
zero and its TAP output must be machine-checked for exactly the 11 registered
names, each once, with no failure, skip or TODO. Source hashes before and
after must match. Any missing or incorrect case, duplicate action, unsafe
allowance, real model signal/start, missing evidence or failed gate rejects
this approach. A setup failure remains inconclusive. The model still does not
qualify the real hung fixture or operating-system process ownership.

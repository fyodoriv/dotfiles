# Reviewer event: parser-backed synthetic gate

**Unqualified proposal:** independent review found that timing out the shell
wrapper can abandon its interpreter child. Do not implement or run this plan.
Consider an exec-only wrapper and in-process runner under a new registration.

Dependency: the independently reviewed parser and discovery in #854 must land
before this experiment runs. Preserve the rejected shell-loop attempt in its
own worktree. This experiment uses the previously reviewed six-case event
adapter and the landed report parser; it does not enable a live hook.

Goal: discover the six event controls and reject false reports. Predict 6/6
event controls and 6/6 wrapper controls pass. Both valid unittest formats
must pass; nonzero exit, missing, skipped, extra/duplicate, and conflicting
summaries must fail. Any accepted invalid report, missing control, process or
network call by the event adapter, or failed ordinary gate rejects this
approach. No reviewer request or chat message is sent.

Copy the independently reviewed adapter and its six controls unchanged from
the preserved event worktree. Record their SHA-256 values before copying and
check equality afterwards. A new bounded CLI adapter reads at most 64 KiB of a
specified report, requires a numeric exit status and calls the landed pure
`valid_report`; it emits only a fixed success or failure diagnostic. Its unit
controls cover both valid formats, invalid and missing paths, oversize input and
nonzero or malformed status. The shell fixture captures the foreground event
test and actual exit, then calls this CLI. It does not print raw child output.
Both the CLI and shell fixture resolve their owned dependencies independently
of cwd. Preserve the parser and its existing tests byte-for-byte.

Before adding the fixture, create six Python wrapper controls named
`test_valid`, `test_nonzero`, `test_missing`, `test_skipped`, `test_extra`,
`test_forged`. For each case use private scratch HOME, a fixed synchronous fake
`python3`, a restricted environment and a five-second direct-child timeout.
The fake supplies the event test report and then `exec`s the actual test
interpreter for the parser CLI. Require the two intended invocations exactly
once and in order. Valid checks both unittest formats; extra checks extra and
duplicate results; forged checks conflicting `Ran`, duplicate `OK`, and
`FAILED` summaries. A fake must not launch descendants or access a network.

Run the named `test_valid` against an absent wrapper before implementation;
require exit 1, one exact unittest FAIL line in either supported Python format
and the fixed diagnostic `event parser wrapper missing`. After implementation
run `JOBS=1 heavy-run python3 hooks/lib/review_ask_event_parser_gate_test.py -v`,
the CLI unit controls, the event controls, and both fixture scripts. Require
all exact names and counts with zero skips, then run the stock Bash fixture
suite and require successful discovery of both fixtures. Finally run the
ordinary unfiltered full gate with `VERIFY_PLAN` unset and request independent
review. Register self-checking red, green and discovery commands before any
implementation; prose is not an oracle. Real event semantics, MCP, optional
channel configuration and delivery remain separate and unproved.

Anchors: #854's report parser and strict fixture contract; Basili, Caldiera and
Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.

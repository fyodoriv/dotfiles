# Reviewer reminder: synthetic event envelope

Goal: prepare a bounded event adapter for the classifier from #851 without
enabling a hook. Predict 6/6 synthetic controls pass, with zero reminders for
the specified failure event, interruption, malformed inputs or unrelated commands. This prepares
an envelope only; it does not prove the real event means reviewers were added.

Create a pure Python function in a new test-only module. It accepts one decoded
synthetic event and returns either a fixed reminder or no reminder. It may
call the existing classifier without changing it. Require `PostToolUse`,
`Bash`, a string command, a response object with `interrupted` exactly false,
and the classifier's exact match. The reminder asks the agent to verify the
reviewer request and draft a chat ask; it must not claim success, include
input text, send a message, read a channel, access the network or install a
hook. No output is allowed for all other events. This deliberately does not
infer a shell exit status from fields whose contract is unqualified.
Require Python boolean identity (`is False`), not equality to zero. A failed
shell command delivered as `PostToolUse` might still receive the verification
reminder; these controls cannot prove otherwise. The negative failure event
is specifically `PostToolUseFailure`.

Use these exact synthetic fixtures. The base event has `hook_event_name` =
`PostToolUse`, `tool_name` = `Bash`, `tool_input.command` =
`gh pr edit 12 --add-reviewer alice`, and `tool_response.interrupted` = false.
The first case requires the fixed string `Verify the reviewer request, then
draft the chat review ask.` The failure case changes only the event name to
`PostToolUseFailure`. The interrupted case changes only the boolean to true.
The unrelated case changes only the command to `gh pr view 12`. The malformed
case checks missing and wrong-type input/response objects and `interrupted: 0`.
The disclosure case adds a synthetic marker to an unrelated input field and
requires exactly the fixed reminder without the marker. The last five cases
require no output except the disclosure case's fixed reminder.

Before implementation create six named tests: `test_matching_event_reminds`,
`test_failure_event_silent`, `test_interrupted_event_silent`,
`test_unrelated_command_silent`, `test_malformed_event_silent`, and
`test_input_is_not_disclosed`. A test-only placeholder returns no reminder.
Run `python3 hooks/lib/review_ask_event_test.py ReviewAskEventTest.test_matching_event_reminds -v`
and require exit 1 with the named test `FAIL` and the fixed reminder in its
assertion. After implementation run exactly:

```sh
JOBS=1 heavy-run python3 hooks/lib/review_ask_event_test.py -v
```

Success requires exit 0, each of the six names exactly once with `ok`,
`Ran 6 tests`, `OK`, no skipped tests, zero unexpected reminders or marker disclosure,
unchanged classifier tests and the ordinary unfiltered full gate. Any reminder
on the four negative classes, disclosure, classifier regression, network or
message action rejects this approach. Independently review the final source.
Inspect the pure adapter for alternate launch paths; tests install network and
process-launch sentinels before importing it and assert zero calls. The local
gate must discover the controls or the preparation cannot merge. Register and
measure gate discovery separately before editing the gate.

Real hook input semantics, exit status, MCP tools, optional channel setting,
activation and delivery need separately registered proof. This experiment does
not satisfy issue #822 by itself. Anchors: #851's classifier contract;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.

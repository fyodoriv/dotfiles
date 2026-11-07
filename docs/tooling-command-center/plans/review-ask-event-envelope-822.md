# Reviewer reminder: synthetic event envelope

Goal: prepare a bounded event adapter for the classifier from #851 without
enabling a hook. Predict 6/6 synthetic controls pass, with zero reminders for
failure, interruption, malformed inputs or unrelated commands. This prepares
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

Before implementation create six named tests: `matching event reminds`,
`failure event silent`, `interrupted event silent`, `unrelated command silent`,
`malformed event silent`, and `input is not disclosed`. The matching case
must fail before implementation. Include malformed nested values and a
synthetic secret marker in the last two controls. Run exactly:

```sh
JOBS=1 heavy-run python3 -m unittest hooks/lib/review_ask_event_test.py
```

Success requires 6/6 passing, zero unexpected reminders or marker disclosure,
unchanged classifier tests and the ordinary unfiltered full gate. Any reminder
on the four negative classes, disclosure, classifier regression, network or
message action rejects this approach. Independently review the final source.
The local gate must discover the controls or the preparation cannot merge.

Real hook input semantics, exit status, MCP tools, optional channel setting,
activation and delivery need separately registered proof. This experiment does
not satisfy issue #822 by itself. Anchors: #851's classifier contract;
Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration.

# App-priority snapshot prediction

The owner removed the seven-day wait on 2026-11-14. The
[same-day experiment](app-priority-same-day.md) replaces the window durations
below; the safety and parity boundaries remain.

The current command repeatedly looks up processes and walks parent chains.
The migration plan asks to try one process snapshot before a Rust port. This
prediction covers a synthetic candidate only. It does not alter the installed
command or interrupt the two before windows.

- **Hypothesis:** One bounded process snapshot can select the same intended
  actions with fewer process lookups, while preserving the current behavior.
- **Measurement:** Add and run `bats tests/app-priority-snapshot.bats` on
  synthetic process tables and configuration inputs. Record exact action
  arguments, order and selected process identity. On a fixed multi-selector
  corpus, count discovery and ancestry subprocesses separately from action
  and clock commands. Use production windows only after their prerequisites.
- **Success:** Zero unexplained action differences on the fixture corpus;
  zero actions on unknown, changed or reused process identities; no real
  process priority changes during fixture tests. The fixed corpus must use
  at least two discovery or ancestry subprocesses in the current selector and
  at most one in the candidate. The production seven-day
  mean must be at most 400 ms and at most 40% of the lower qualifying before
  window, after the before windows agree within 20%. Every before and after
  window needs at least 1,000 valid tagged samples.
- **Pivot:** Keep the existing command if exact-name or pattern semantics,
  parent ancestry, process identity, snapshot completeness or failure behavior
  cannot be established. An incomplete snapshot or timing window is not a
  successful result.
- **Anchor:** `rust-migration.md` step 2, `app-priority-timing.md`, and the
  current `bin/app-priority` behavior.

## Boundaries to settle before implementation

The fixture must cover names with spaces, regular-expression patterns,
multiple matches, absent processes, parent loops and the 16-level ancestry
limit. It must cover processes that exit, change ancestry or reuse a PID
between observation and action. A snapshot must not silently truncate command
lines, accept ambiguous rows, or equate an unreadable process with a safe one.
The design must explain how it preserves process identity across the action
boundary, or refuse the candidate. Record the platform-specific `pgrep` and
`ps` semantics and their differences; an assumed equivalent regex is not proof.
Rechecking a PID before a separate action still leaves a race. Apple
[documents](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setpriority.2.html)
`setpriority(PRIO_PROCESS, ...)` as selecting a process by PID, and separately
[warns](https://developer.apple.com/documentation/xpc/xpc_connection_get_pid%28_%3A%29)
that macOS can reuse PIDs. Together these facts do not establish an
identity-bound action or prove that no such primitive exists. Identify an
actual platform primitive that closes the action boundary or pivot. In a
[pinned Apple source revision](https://github.com/apple-oss-distributions/system_cmds/blob/408bba7453608006b89772db185defbac8fe2fd0/taskpolicy/taskpolicy.c),
`taskpolicy` uses PID-based priority calls for background changes and a
separate PID lookup for QoS. This source does not identify the installed
binary or prove an identity-bound replacement. If an
ancestry lookup fails, the current script treats the process as noninteractive
and backgrounds it. A candidate that skips that action is a behavior change,
not parity: stop and resolve that difference separately before deployment.

Exercise present, absent and unreadable configuration, inline comments,
literal spaces and an unterminated final line. A present config replaces the
defaults; wildcard or dot selects pattern matching. Cover duplicate selectors,
overlapping matches, action argument and order differences, failed commands,
and the difference between one snapshot and sequential lookups. Validate Darwin
`pgrep` and `ps` examples independently; synthetic examples alone cannot
prove platform equivalence.

Set both HOME and XDG_CONFIG_HOME to scratch locations and control PATH in the
fixture. Mock every priority action. Existing tests must not run against real
configuration paths. Use fake process tables and action sinks. Do not send priority
changes or signals to live processes. Independently review the fixture and
identity design before a live candidate is deployed. The current process can
already race; this experiment must not hide or increase that risk. No before
window can be repaired with a later snapshot.

## Existing fixture isolation correction

Root cause: the existing app-priority test setup changes HOME but inherits
XDG_CONFIG_HOME. Several tests remove a configuration file through the latter.

- **Hypothesis:** Setting XDG_CONFIG_HOME inside the test's disposable HOME
  keeps the inherited configuration canary untouched and preserves the test
  suite's behavior.
- **Measurement:** Run one existing default-config test as a child Bats run
  with HOME and XDG_CONFIG_HOME set to separate disposable directories. A
  parent regression test checks the inherited configuration canary after the
  child exits. Run the touched test suite in hosted CI.
- **Success:** The canary is removed before the fix, remains byte-identical
  after it, and the selected child test succeeds in both observations. The
  regression passes and hosted CI is green.
- **Pivot:** Stop if the child can reach a real configuration, an action
  command is not mocked, the canary changes after the fix, or the selected
  test's result changes. Never use a real configuration to reproduce this.
- **Anchor:** `tests/app-priority.bats` setup and default-config tests; the
  independent fixture review on 2026-11-13.

## Task-port identity lead (2026-11-14)

Apple's [task-port event documentation](https://developer.apple.com/documentation/endpointsecurity/es_event_get_task_t)
describes an event for access to a task-control right; it does not grant that
right or change priority. Its [Mach IPC guidance](https://developer.apple.com/documentation/xcode/conforming-to-mach-ipc-security-restrictions)
describes permission-checked identity-token conversion in protected exception
messages. Those sources do not establish how this tool would obtain a token for
arbitrary target apps, or an owner-accessible equivalent to both background
priority and QoS actions. Apple's archived [SIP guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/System_Integrity_Protection_Guide/RuntimeProtections/RuntimeProtections.html)
describes task-port restrictions for protected processes; it does not establish
access for every other target.

Independent review found no qualified replacement in these sources. The pinned
`taskpolicy` source above does not identify this Mac's installed binary. This
research does not prove that no other API exists. No target process was accessed
or changed. Keep the identity pivot and both baseline windows unchanged.

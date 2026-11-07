# Reviewer event: unregistered in-process design

The proposed parser-backed event gate could leave its interpreter alive after
the wrapper times out. Do not run it. An independent review identified a
possible narrower design: the wrapper uses shell builtin `exec` to replace
itself with one interpreter, and the interpreter loads the six event tests and
the #854 parser in-process. The owner can then time out and wait for that same
direct process. This is not proof about escaped descendants.

Before registering a measurement, pin an absolute interpreter and clean
environment; review all imports and controls for subprocess and network paths.
The runner must capture the actual unittest result and report privately, restore
all streams and test monkeypatches on exceptions, and pass the real result to
the parser. Test genuine failing and skipped suites, not only manufactured
reports. The fixture driver needs a finite, childless fake that records its PID,
plus a separately controlled timeout and direct-child reap check. Define the
two accepted unittest name formats, red and green named oracles, source hashes,
stock-shell discovery and cleanup before running anything. A callback, injected
status or fake report alone does not prove the actual suite ran.

This is design work only. It authorizes no process observation, test, live
reviewer request, hook installation or chat message. Real event semantics and
MCP integration remain unproved.

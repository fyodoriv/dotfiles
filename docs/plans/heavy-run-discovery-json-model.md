# Discovery JSON test model

The discovery JSON model is a test fixture. It checks a conservative decision
on raw JSON bytes without running the input. It does not change the queue guard
or establish how the real tool executor interprets JSON.

Run `JOBS=1 heavy-run bats tests/heavy-run-discovery-json.bats` to check the two
exact discovery probes and the 30 fallback cases. The suite uses an isolated
Python interpreter, scratch configuration and synthetic execution markers.

The prediction and frozen cases were registered in the coordination plan at
commits `fa22c25`, `b4fde5a` and `e196a9f` on the tooling task coordination branch. Production use needs
separate executor-parity, parser-availability and failure-behavior evidence.
A fallback from this model does not prove that the current guard handles an
arbitrary input safely.

The read-error control injects a synthetic error after Python starts. It does
not test operating-system pipe errors or interpreter startup failures.

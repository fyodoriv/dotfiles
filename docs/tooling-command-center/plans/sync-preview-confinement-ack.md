# Pin confinement preflight evidence

Supplement `e800168` and `5dcb91c` before implementation. The unrestricted
listener records the fixed byte, sends a fixed `ACK`, and the child verifies
that exact acknowledgement before exiting. The restricted listener must record
no accepted byte.

The canonical scratch path must match only ASCII letters, digits, `/`, `_`,
`-` and `.`; otherwise setup is inconclusive. Require exactly one policy
placeholder and no other interpolation. Record the rendered policy privately.
A policy startup error or unsupported operation is setup-inconclusive, never
proof of denial.

Pin Node version 24.21.0 with SHA-256
`e4b5a3af0e05c75de2eae013904145f40fe7fc2a6e6f17510128bf45cca4e79b`
and the platform sandbox executable with SHA-256
`58839ef01b4eef8aac0d2aa8f9d1c074ae45aafe3533965b030672450064acc8`.
Resolve both physical absolute paths before launch, verify the hashes before
and after, and use only those absolute executables with a clean PATH. Any
identity mismatch is inconclusive and needs a newly registered preflight.

On timeout or catchable interruption, send TERM, then bounded KILL only to the
still-live owned child handle, await `close`, cancel timers and close listeners.
Never signal a reaped PID. Uncertain terminal state is inconclusive. Limit
captured stdout and stderr while reading; exceeding the cap fails the control.
Create the private receipt exclusively within the mode-700 task-owned parent;
keep only versions, hashes, named outcomes and cleanup status. The sandbox
allows process creation for startup: absence of descendants is a property of
the fixed reviewed child programs, not an OS-enforced guarantee. No claim is
made about general host-read isolation or production CLI behavior.

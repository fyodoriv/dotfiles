# Register child-process confinement preflight

The previous in-process measurement candidate failed its registered final
gate and remains preserved. A distinct path is a child-process integration
measurement using real CLI previews and separate synthetic failing-runner
children. Before building that measurement, qualify whether this Mac can
confine its children to scratch writes and deny network access.

Goal: make it possible to test previews without changing user files or
contacting a network. Question: can a child under the platform sandbox write
inside one owned scratch directory while outside writes and loopback network
connections fail? Predict four of four named controls pass: scratch write and
read succeed; a write to a task-owned sibling outside the allowed directory is
denied and leaves its preseeded bytes unchanged; an attempt to connect to a
test-owned loopback listener is denied; an unrestricted control reaches that
listener. Require all owned children and listener processes to exit and be
reaped, and no user paths, external network, private content, or real config.

After this registration, create a standalone test-only preflight with the
exact command `JOBS=1 heavy-run node scripts/sync-preview-confinement-preflight.mjs`.
The script uses a fresh mode-700 task-owned parent and separate sibling paths;
it writes the platform policy into scratch and invokes the platform sandbox by
absolute path. Read access may be broad enough to start the pinned Node binary,
but writes are limited to the allowed scratch child, and networking is denied.
Use only a loopback listener created by the preflight, bounded child timeouts,
and synthetic bytes. No outside path other than the task-owned sibling is a
write target. Report four individually named results without paths or payloads.
Prove the listener is reached in the unrestricted positive control before the
network-denial claim. Verify cleanup by checking exit and reap of each owned
child and listener.

Success: 4/4 exact controls, no missing or skipped case, zero unexpected writes,
zero surviving owned processes, and independent review. Any unexpected allow,
missing denial, missing positive control, wrong process cleanup, or unavailable
platform confinement rejects this approach. A setup failure is inconclusive;
record it and redesign. A successful preflight does not itself prove the CLI
preview or failure behavior. Register the later source-bound CLI and runner
measurement separately before running it.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration; observed macOS sandbox executable on this host.

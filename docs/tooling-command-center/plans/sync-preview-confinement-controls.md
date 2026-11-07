# Freeze child confinement controls

Supplement `e800168` before implementing the preflight. Resolve the current
Node executable and `/usr/bin/sandbox-exec` to physical absolute paths and
record their versions and hashes privately. Launch direct owned children with
an empty environment except scratch `HOME` and `TMPDIR`; the fixed Node child
programs use no process-creation API. Create a fresh mode-700 parent, its
mode-700 `allowed` child and distinct `outside` sibling. Resolve their real
paths, verify ownership and modes, and reject symlink or containment surprises.
Use the canonical allowed path encoded as a JSON string in this exact policy:

```scheme
(version 1)
(deny default)
(allow process-exec process-fork)
(allow file-read*)
(allow file-write* (subpath ALLOWED_JSON_STRING))
(allow sysctl-read)
(deny network*)
```

The literal `ALLOWED_JSON_STRING` is replaced once by `JSON.stringify` of the
canonical allowed path; no shell evaluates it. Verify the substituted policy
contains exactly one substitution. Broad reads are allowed; this does not prove
other host paths are unreadable.

Run these fixed child programs with `node -e`, passing only synthetic paths or
loopback port as separate arguments. Their exit codes are the oracle; errors
other than the stated permission errors are failures or inconclusive setup.

1. Restricted scratch: write the fixed text `scratch-ok`, read it back, exit 0
   only on equality.
2. Restricted sibling: after the parent has written, read, reset and verified
   fixed `outside-seed` bytes, try to replace them; exit 0 only on `EPERM` or
   `EACCES`. Parent verifies the exact seed remains.
3. Unrestricted loopback: connect to a parent-owned loopback listener that has
   emitted its ready signal, send one fixed byte and exit only after the parent
   records acceptance. Wait for this child to exit and be reaped before the
   next control.
4. Restricted loopback: use a fresh ready parent listener and attempt the same
   connection; exit 0 only for `EPERM` or `EACCES`, with no accepted-byte
   marker. Timeout, `ECONNREFUSED`, startup or other errors are not denial.

The four programs and their arguments must implement only those operations;
they never read or write a user path or contact an external address. Bound
individual children to five seconds and the whole run to 30 seconds. Keep
retained handles for each direct child, record `close` and exit, and terminate
only those owned children on timeout or catchable interruption. Close each
parent listener on every path. A failed spawn, missing close, uncertain reap,
or timeout is inconclusive, not success. Bound captured output and retain a
private receipt with executable identities, policy hash, named outcomes and
cleanup results, without storing user paths or data. Success and pivot remain
those in `e800168`; this preflight qualifies only the listed operations and
loopback network denial.

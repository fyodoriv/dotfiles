# Temporary browser acquire wait (#555)

Registered before implementation.

## Hypothesis

A second owner with `--wait --timeout 3` acquires immediately after the holder releases, instead of exiting 3. A held lock past the timeout still exits 3. Each wait prints the holder once on stderr. Same-owner re-acquire, stale-lock takeover, and no-wait behavior keep their existing outcomes.

## Measurement

`bats tests/temp-browser.bats`, then `make check`.

## Success

Release and timeout controls pass; exactly one holder notice appears per wait; invalid timeouts exit 2 without launching a browser; every existing browser lifecycle test stays green.

## Pivot

If waiting cannot reuse the atomic mkdir/stale-lock path without a second browser or wrong-owner takeover, keep the immediate refusal and revise the design. Do not kill the current holder or bypass its lock.

## Independent-review controls

Registered before the review fixes.

Two failures remain after the first wait implementation: cleanup can overlap two browsers on one port, and lease expiry during waiting prints the holder twice. Predicted counts after the fix: zero overlap and one notice. Stop the old browser before making its lock available; use an atomic rename only after that stop. Add a TERM-ignoring old-process control and an expiry-during-wait control. The original release race and all existing controls must stay green. Any second launch before the old exit rejects the approach.

## Concurrent-cleanup control

Registered before the next review fix.

A delayed releaser and a waiter can both clean the old lock. Without an identity check, the delayed rename can delete the replacement. Predicted missing replacement locks: one; after the fix: zero. Serialize the short rename section and compare the original lock inode before moving it. A delayed cleanup skips a different inode. Add a delayed-first-rename regression and retain the no-overlap, one-notice, and full lifecycle controls.

## Interrupted-cleanup recovery controls

Registered before the recovery fix.

Predicted wedges: two. A cleanup marker left by a dead process must not block release, and an expired acquisition with no browser PID must be recoverable. Record the acquiring shell PID when the lock is created and the cleanup PID when its marker is created. A live acquiring or cleanup PID keeps the lock; a dead one permits retry. A PID-less legacy record still requires expiry evidence. Add dead-cleanup and expired-initialization controls plus a live-initialization guard. Existing race and lifecycle controls must stay green.

## Atomic cleanup-marker registration

Registered before the marker fix.

The two-step cleanup directory/PID write admits a second owner. Predicted replacement-lock loss: one; after the fix: zero. Create each ownership record as `PID random-token` before one atomic hard-link operation. A dead record is removed only when its complete token still matches. Empty records cannot authorize removal. Retain every cleanup, recovery, and wait control.

## Anchor

Issue #555's queueing contract; Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.

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

## Anchor

Issue #555's queueing contract; Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration.

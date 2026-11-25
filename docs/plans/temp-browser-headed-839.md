# Make sign-in browsers visible

Issue: #839. A headless disposable browser has no window for a person to
use during sign-in. Add `acquire --headed` and a headless warning on stderr.

Hypothesis: an explicit visible-window option prevents handing a person a
headless sign-in browser, while port-only stdout remains usable by callers.

Measurement: hosted `tests/temp-browser.bats` with synthetic launch hooks and
the existing fake Chrome launcher. Check headed selection, headless stderr,
and same-owner reuse. No signed-in browser or credentials are used.

Success: all registered cases and existing tests pass; the launch hook sees
headed mode when requested; stdout contains only the CDP port.

Pivot: any invisible reuse accepted as headed, changed port output, or loss
of keychain isolation rejects the change.

Anchor: issue #839 and `docs/agent-browser-policy.md`.

The on-disk per-user lease owns the browser mode until release or stale-lock
cleanup. A headed request cannot silently reuse that owner's headless lease.
The launch hook keeps its profile and port arguments; its environment carries
the selected `TEMP_BROWSER_HEADED` mode.

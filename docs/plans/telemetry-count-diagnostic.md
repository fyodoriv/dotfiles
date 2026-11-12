# Terminal telemetry test diagnostic

Registered before instrumentation on 2026-11-11. One local gate saw a
request-count assertion fail; the actual count and cause are unknown. The
case later passed alone. The test's command-log writer is asynchronous. Under
Bats, the detached daily sender is disabled unless
`DOTFILES_TELEMETRY_SPAWN` is set; the case does not deliberately set it.
The subsequent `daily` command runs in the foreground. A log line is not
proof that the background writer exited.

Hypothesis: explicitly disabling the detached sender in this case and adding a
bounded, content-free count receipt makes planted request-count mismatches
observable without changing production telemetry.

Measurement: test counts 0, 1 and 3 against expected 2 using synthetic data;
each must report expected and observed numeric counts and whether the
foreground command returned. Reject untrusted or malformed fields as unknown.
Add a canary to synthetic input and prove it never appears in the receipt.
Keep the exact synthetic payload assertion in the fixture. Run the focused
Bats tests locally and the affected suite in hosted CI.

For the separately enabled detached path, use the existing test-owned sender
fixture with an end-of-script marker and a bounded wait. A marker proves the
sender reached that point, not that its process exited; a timeout is unknown.
Never inspect or signal unowned processes. Do not claim the target test
observes detached-process completion.

Success: all three planted mismatches produce the expected bounded receipt;
zero canary disclosures; the foreground-return observation is accurate; the
existing synthetic sender reaches its marker; all affected tests pass. Pivot:
any raw payload, unsafe process action, misleading completion claim or missing
marker rejects the instrumentation. Keep the original failure's cause unknown
until evidence shows it.

Anchor: the `telemetry-terminal-request-count-diagnostic` task; Basili,
Caldiera and Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

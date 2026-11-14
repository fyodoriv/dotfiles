# Native status guard trial

Register before implementation. The shell shortcut did not qualify. Trial a
small Rust JSON reader for a narrow literal `git status` case. It must hand
all other input, unchanged, to the existing guard. Duplicate target keys,
escapes, malformed JSON and unknown syntax always use the old guard.

- **Hypothesis:** Native JSON reading preserves guard decisions and output
  while cutting the registered dangerous-Git status row by at least half.
- **Measurement:** Hosted macOS compares the installed wrapper with the
  existing guard on valid, duplicate, malformed and hostile inputs. Run the
  registered performance row and the 15-sample peak-RSS baseline and
  candidate checks under `heavy-run --exclusive`.
- **Success:** Zero parity failures or false permits; status-row ratio at
  most 0.50; stable baseline memory ratio 0.95–1.05; candidate/base median
  RSS at most 1.10; the existing 20 A/A checks remain valid; locked offline
  build succeeds within the existing budget.
- **Pivot:** Any parity or safety failure keeps the old guard active. A
  missed benefit after this port attempt records an exception under the
  existing task rule; an invalid or missing measurement stays inconclusive.
- **Anchor:** [the migration plan](rust-migration.md), the earlier shortcut
  result, and `tests/agent-hooks-block-dangerous-git.bats`.

This trial does not port the heavy-run hook or qualify a live switch. The
fallback bridge remains temporary until the whole selected boundary can pass
gate G without the former implementation.

The first hosted comparison invokes the candidate directly against the
existing guard in a disposable environment. It can reject a candidate, but it
does not substitute for the registered gate row or installed-wrapper proof.

## In-process fallback boundary

Register before the next implementation. Keep the existing shell guard as the
process that reads input and owns fallback. After that read, invoke the native
reader only as a yes-or-no check. A rejected input or reader error continues
through the same shell guard with the same captured bytes. This avoids leaving
a separate fallback guard process behind if the native reader is interrupted.

- **Hypothesis:** This boundary preserves the existing fallback lifecycle and
  still meets the 0.50 status-row and 1.10 memory limits.
- **Measurement:** Run the existing guard safety suite and the hosted
  scratch-entry comparison, memory samples, and registered performance gate.
- **Success:** Zero changed guard decisions or output; all safety tests pass;
  gate ratio is at most 0.50; stable baseline memory ratio is 0.95–1.05 and
  candidate memory ratio is at most 1.10.
- **Pivot:** Any mismatch, failed safety check, unstable baseline, or missed
  threshold retains the old installed guard.
- **Anchor:** Gate G in [the migration plan](rust-migration.md) and the
  native direct-reader fixture results.

## Process-replacement fallback

Register before implementation. The shell-owned reader boundary preserved
the 33 guard safety cases and same-path output in the hosted fixture, but its
median timing ratio was 0.651, above 0.50. Trial a native entry point that
replaces itself with the existing shell guard when it cannot prove a literal
status command. An unlinked, owner-only shared-memory object carries the input
to that replacement; it is closed when the guard exits. No payload is logged.

- **Hypothesis:** Process replacement preserves fallback output and lifecycle
  while removing enough startup work to meet the status-row target.
- **Measurement:** Repeat the existing guard safety suite, same-path parity,
  15 + 15 baseline and 15 candidate RSS samples, and queued performance gate
  on hosted macOS. Check that the replacement retains the original PID.
- **Success:** Zero parity or safety failures, no persistent shared-memory
  object, the replacement keeps the PID, gate ratio is at most 0.50, and the
  baseline and candidate RSS ratios meet 0.95–1.05 and 1.10 respectively.
- **Pivot:** Any missed bound, cleanup failure or changed decision retains the
  old guard. Invalid evidence remains inconclusive.
- **Anchor:** [the hosted shell-boundary result](https://github.com/fyodoriv/dotfiles/actions/runs/43627487962)
  and the migration plan's gate G.

The first process-replacement attempt failed before replay: macOS returned
`Device not configured` for the shared-memory input path. The object was
unlinked before any attempted write. See [run 43627918779](https://github.com/fyodoriv/dotfiles/actions/runs/43627918779).
It is rejected and never installed.

## Shell-owned fallback with a here-string

Register before implementation. Return to the shell-owned fallback boundary.
Use a here-string to feed the native check instead of starting a `printf`
pipeline. The existing shell keeps its captured input and handles every
non-match. The added newline is JSON whitespace; ambiguous input still falls
back to the original guard.

- **Hypothesis:** Removing the extra pipeline process preserves parity and
  reaches the existing 0.50 status-row ratio.
- **Measurement:** Repeat the hosted guard safety suite, same-path parity,
  memory samples, and exclusive performance gate.
- **Success:** All guard decisions and output match; the gate ratio is at most
  0.50; the baseline and candidate memory ratios meet 0.95–1.05 and 1.10.
- **Pivot:** Any mismatch, failed sample or missed bound retains the old guard.
- **Anchor:** The rejected shell-owned and shared-memory trials above.

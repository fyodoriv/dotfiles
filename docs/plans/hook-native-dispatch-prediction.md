# Hook native dispatch prediction

Registered before changing the dispatch lookup on 2026-11-14. The installed
path measured a 0.698 gate ratio and missed the 0.50 target.

**Hypothesis:** Replace the external symlink lookup with Bash file-identity
checks while retaining the content checksum and fail-closed receipt. This
removes one child process and reduces the installed gate ratio to at most 0.50.

**Measurement:** Hosted `hook-status-fixture` runs the existing safety cases,
exclusive performance gate and paired timing and memory fixture.

**Success:** No changed guard verdicts, corrupt artifacts fall back, missing
receipts block, gate ratio at most 0.50, stable baseline RSS and candidate RSS
at most 1.10. **Pivot:** If the gate remains above 0.50, retain the existing
guard and record the result; do not claim a port or weaken the safety checks.

**Anchor:** `rust-hook-status-experiment.md`; Basili, Caldiera, Rombach 1994;
Munafò et al. 2017.

## Dispatch before endpoint setup

Registered before changing the order on 2026-11-14. The installed dispatch
measured 0.631 and retained the old hook. Its fast path still runs endpoint
setup before inspecting the input, although the native status decision uses
absolute helper paths and does not need that environment.

**Hypothesis:** Trying the integrity-checked native dispatch before endpoint
setup cuts the gate ratio to at most 0.50. Unknown inputs still execute the
original guard, including endpoint setup, and native failures still block.

**Measurement:** Hosted macOS runs the existing guard and dispatch safety
controls, installed-entry parity, the exclusive performance gate, and the
registered memory comparison. **Success:** No changed decisions, no false
permits, ratio at most 0.50, and memory within the existing bounds. **Pivot:**
Any safety difference or missed threshold retains the existing shell guard.

**Anchor:** the 0.631 hosted gate result, `rust-agent-hooks`, and Munafò et al.
2017.

### Hosted result

The [installed-path run](https://github.com/fyodoriv/dotfiles/actions/runs/43643440449)
passed the safety and fixed-input parity checks. The registered gate ratio was
0.378. The three additional status-variant ratios were 0.382, 0.417 and 0.421,
within their 0.80 limits. Baseline and candidate peak-RSS ratios were both
1.00. These are controlled hosted results, not live usage measurements.

The shortcut handles only conservative status input. Other commands still run
the original shell guard, so this result does not complete the full hook port.
Lesson: qualify the actual supervised entry point, including its setup and
fallback, rather than extrapolating from a direct binary fixture.

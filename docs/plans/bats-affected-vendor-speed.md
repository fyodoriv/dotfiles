# Affected-test selection for large changes

Register before implementation. The hosted check for the offline Rust
candidate spent 11 minutes 12 seconds between skipping the performance gate
and starting two affected tests. Its diff included 458 vendored files. The
selector currently starts a search for every changed-file/test pair.

- **Hypothesis:** A literal basename prefilter reduces searches for large
  changes while preserving every test and `--pairs` result.
- **Measurement:** On hosted macOS, compare the old and new selectors on the
  same scratch repository with the real Bats test corpus and a fixed set of
  20 changed vendor paths. Record wall time and compare the complete outputs.
  Run the existing selector tests and controls for derived root variables.
- **Success:** Both output modes match exactly, all selector tests pass, the
  new median is at most half the old median, and it completes in 30 seconds.
- **Pivot:** Any missing match, changed pair, failed control, or missed timing
  retains the old selector. Do not skip Rust checks or alter their gates.
- **Anchor:** [hosted run 43621586222](https://github.com/fyodoriv/dotfiles/actions/runs/43621586222),
  `bin/bats-affected`, and the existing `tests/bats-affected.bats` contracts.

## Keep the benchmark runnable after the optimization ships

The required selector job for the signer writer passed 91 Bats checks.
Its timed fixture then failed at `scripts/benchmark-bats-affected.py:32`.
The candidate picked `rust/vendor/itoa/benches/bench.rs` first and
treated it as relative to `rust/vendor/libc`. The local path-only check
reproduced the same exception. The PR base also already includes the
prefilter from #674. Comparing that base with a small maintenance change
cannot measure the original twofold gain.

- **Hypothesis**: Keep one known changed file under the generated test's
  declared root, and use the original prefilter parent as the timing
  baseline. Compare current-base and candidate outputs independently.
- **Measurement**: Run the required benchmark on hosted macOS inside
  its existing exclusive reservation. Check exact results for both
  output modes across the historical, current-base and candidate
  selectors. Record six timed samples for each timed selector.
- **Success**: All 20 files are staged, both output modes match, the
  planted dependency is selected, and the existing at-most-half and
  30-second limits pass against the original prefilter parent
  `1a96d12a8bf0b42df0fba340bf933d4c79ecd2d2`.
- **Pivot**: Missing parity, missing changed dependency or a failed
  original timing limit blocks the work. Do not lower this threshold.
- **Anchor**: [selector job 134601446885](https://github.com/fyodoriv/dotfiles/actions/runs/44244922576/job/134601446885)
  and [original optimization #674](https://github.com/fyodoriv/dotfiles/pull/674).

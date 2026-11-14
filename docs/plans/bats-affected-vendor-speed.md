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

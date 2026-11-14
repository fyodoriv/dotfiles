# Hook status fast-path prediction

Registered before the experiment on 2026-11-11. The dangerous-Git hook's
linked-checkout baseline is 44.3495 ms: the median of 20 `base_min`
observations in [the hook baseline](rust-hook-baseline-2026-11-11.md). The
20 clean and 20 linked A/A checks passed. The exact gate row remains
`git status` at the existing entrypoint.

## Hypothesis

A conservative fast path for plain `git status` and known read-only status
flags cuts the gate row ratio to at most 0.50. It preserves the old status,
stdout and stderr for every registered case, including malformed JSON,
missing tools and hostile shell syntax. Unknown syntax follows the old path.
The heavy-run hook remains unchanged in this experiment because skipping its
Perl parser can change a parser failure into an allow.

## Measurement

First collect two baseline peak-RSS medians: 15 invocations each under
`/usr/bin/time -l`, with the gate row's JSON input and an exclusive
`heavy-run` slot. Set `DOTFILES_DIR` to this checkout, and use the same
`bash -c`/`exec` wrapper for baseline and candidate so hook stderr can be
checked separately. The wrapper can affect peak RSS. The A/A ratio must be
0.95 to 1.05. Record every result and
failure in a private scratch file. A missing value makes the result
inconclusive. Compare a candidate's 15-run median to the lower baseline median; R_M
must be at most 1.10. If any trial is invalid, stop and mark the run
inconclusive; report the first invalid trial rather than claiming 30 samples.

Compare old and candidate hook status, stdout and stderr in a scratch fixture
for `git status`, `git status --short`, `git status -s -b`, and
`git status --porcelain=v1`, plus appended commands, substitutions,
heredocs, quotes, malformed and missing JSON fields, and missing or spoofed
helper tools. Retain the existing dangerous-Git tests. Require zero changed
verdicts and zero new false permits.

Measure the three status variants above with 15 order-balanced old/candidate
pairs each under an exclusive `heavy-run` slot. The median candidate/old ratio
must be at most 0.80 for each variant. Run the unchanged performance gate for
its registered row; its ratio must be at most 0.50. Queue wait is not execution
time. Preserve the raw samples and validity outcomes privately.

## Provisional peak-RSS baseline (2026-11-12)

The second retained baseline used source revision
`2b531529bb9bc6b787363aa96afc689b8940ff4e`. The two 15-sample
windows each had a median peak RSS of 4,784,128 bytes. Their ratio was
1.000, within the registered 0.95–1.05 A/A range. Applying the 1.10
calculation gives 5,262,540 bytes, but this is not a qualified candidate bound.

A separately retained request and startup audit were checked against the
private launch, wait and sample receipts. Independent review confirmed the
15 + 15 counts, medians, ratio and retained validation flags. This is trusted
local correlation, not kernel lock attestation. It does not rule out
same-user tampering or transient changes; source, tool and load flags remain
controller observations. A later independent review found that the retained
audit does not establish the effective helper and executable/interpreter chains.
The baseline is therefore inconclusive for qualification. A later probe cannot
repair the evidence for this run. Raw samples and launch evidence stay private.

An earlier 15 + 15 run lacked this retained binding and remains provisional.
Do not use it as the baseline. This record does not establish a performance
improvement or relax the parity and gate requirements above.

## Success and pivot

Success requires all parity and safety checks, the RSS floor and bound, the
three representative ratios, and the registered gate ratio. If any check
fails, or the measurements are contaminated or unavailable, retain the old
hook. A narrow win on the benchmark alone is not enough. The second hook and
native delivery remain separate work.

Anchor: the migration plan's gate G and hook task; Basili, Caldiera and
Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

## Installed dispatch result (2026-11-14)

The [delivery draft](https://github.com/fyodoriv/dotfiles/pull/680) supervises
the Rust helper and verifies its checksum. Its first corrected installed-path
[gate run](https://github.com/fyodoriv/dotfiles/actions/runs/43638960781)
measured 0.698, above the required 0.50. A pre-registered replacement of the
external symlink lookup with a Bash file-identity check passed the focused
safety tests, but its [gate run](https://github.com/fyodoriv/dotfiles/actions/runs/43639666649)
measured 0.631. The candidate remains uninstalled. Both ratios fall between
the task's success and exception-pivot thresholds, so this is inconclusive,
not a port or an exception. The second hook still needs its own result.

Lesson: benchmark the real supervised, integrity-checked delivery path before
claiming a speedup. An earlier scratch wrapper measured 0.166 but did not
provide the same failure handling. Keep the shell guard while the production
path misses its target.

## Heavy-run guard shortcut (2026-11-14)

The [shortcut draft](https://github.com/fyodoriv/dotfiles/pull/682) kept the
existing parser and skipped the later scan only for the exact parsed status
command. Its [hosted performance run](https://github.com/fyodoriv/dotfiles/actions/runs/43640123377)
measured a 0.840 ratio, above the required 0.50. The registered pivot retains
the existing hook. This is a failed cheaper fix, not a Rust port attempt or a
completed exception decision.

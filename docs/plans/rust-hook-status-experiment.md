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
`heavy-run` slot. The A/A ratio must be 0.95 to 1.05. Record every result and
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

## Success and pivot

Success requires all parity and safety checks, the RSS floor and bound, the
three representative ratios, and the registered gate ratio. If any check
fails, or the measurements are contaminated or unavailable, retain the old
hook. A narrow win on the benchmark alone is not enough. The second hook and
native delivery remain separate work.

Anchor: the migration plan's gate G and hook task; Basili, Caldiera and
Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

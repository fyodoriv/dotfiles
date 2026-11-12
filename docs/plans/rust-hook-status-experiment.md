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

Measure all four status variants listed above with 15 order-balanced
old/candidate pairs each under an exclusive `heavy-run` slot. The earlier
wording said three although it listed four; all four must pass. The median candidate/old ratio
must be at most 0.80 for each variant. Run the unchanged performance gate for
its registered row; its ratio must be at most 0.50. Queue wait is not execution
time. Preserve the raw samples and validity outcomes privately.

These four variants are supplementary checks of the same hook slice. They do
not establish independent gate-qualified results for the non-row workloads.
The unchanged `git status` budget row remains the benefit decision.

## Qualified peak-RSS baseline (2026-11-12)

The second retained baseline used source revision
`2b531529bb9bc6b787363aa96afc689b8940ff4e`. The two 15-sample
windows each had a median peak RSS of 4,784,128 bytes. Their ratio was
1.000, within the registered 0.95–1.05 A/A range. The candidate's median
must be at most 5,262,540 bytes to meet the 1.10 bound.

A separately retained request and startup audit were checked against the
private launch, wait and sample receipts. Independent review confirmed the
15 + 15 counts, medians, ratio and retained validation flags. This is trusted
local correlation, not kernel lock attestation. It does not rule out
same-user tampering or transient changes; source, tool and load flags remain
controller observations. Raw samples and launch evidence stay private.

The candidate retry mechanically passed the two-window sample and arithmetic
checks. Each 15-sample window had a median of 4,767,744 bytes, below the
registered 5,262,540-byte bound; their A/A ratio was 1.000. A later independent
review found that the retained audit does not establish the actual resolved
helper and all selected executable/interpreter chains. The result is
**provisional and inconclusive for qualification**. Do not retrofit a later
probe as evidence of the earlier run. The first candidate attempt had no
samples because its initial load gate failed and also remains inconclusive.
Neither result establishes parity or speed.

An earlier 15 + 15 run lacked this retained binding and remains provisional.
Do not use it as the baseline. This record does not establish a performance
improvement or relax the parity and gate requirements above.

## Success and pivot

Success requires all parity and safety checks, the RSS floor and bound, the
four representative ratios, and the registered gate ratio. If any check
fails, or the measurements are contaminated or unavailable, retain the old
hook. A narrow win on the benchmark alone is not enough. The second hook and
native delivery remain separate work.

Anchor: the migration plan's gate G and hook task; Basili, Caldiera and
Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).

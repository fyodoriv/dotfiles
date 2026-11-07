# Register model review controls

Independent review found that the first 30 controls do not show whether a NUL
in unrelated metadata is rejected, and the model does not catch an input read
error. The previously registered result remains recorded separately.

Goal: make the test-only model refuse both inputs. Question: do an allowed
command with a NUL in nested metadata and a failed input read both return
`fallback` without dispatch? Predict 2/2 fallbacks and zero dispatch, while all
30 existing cases remain passing. Measure with
`JOBS=1 heavy-run bats tests/heavy-run-discovery-json.bats`: exactly 32 ordered
passing cases, P01, P02 and N01–N30, no skips or TODOs. N29 contains the exact
allowed command and `\u0000` in a nested metadata value. N30 supplies a
scratch directory as standard input, first verifying that reading it raises
`OSError` on the isolated interpreter. Require N30 to fail before the fix;
then catch the read error and require all 32 to pass. Preserve the original
30-case evidence. Any wrong result, dispatch, missing control or repository
gate failure rejects the approach; a setup failure is inconclusive and needs a
new design. Run the same fresh selected-file gate and independent review.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al.
(2017), preregistration; RFC 8259 sections 4 and 8.

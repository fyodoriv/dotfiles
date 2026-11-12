# Hook executable shebang control prediction

Hypothesis: a pure decoder of already-read, bounded script-header bytes can
identify one absolute interpreter and at most one simple argument without
executing a tool. This is preparation for input review, not a qualified run.

Measurement: `python3 tests/hook_shebang_test.py` and independent review.

Success: accept the registered absolute-path examples and exact size boundary;
reject at least eight malformed, overlong, relative, ambiguous or unsupported
examples, including `/usr/bin/env`. Pivot: reject any ambiguous form and keep
the executable chain unresolved. Inspect the tracked wrapper as source bytes
only. No selected runtime tool is claimed to match those bytes.

Anchor: [future input audit](hook-effective-input-audit.md) and
`docs/plans/rust-hook-status-experiment.md`.

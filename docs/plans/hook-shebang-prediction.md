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

The decoder checks only supplied header bytes. It does not read a selected
file, follow links, verify an interpreter, or prove which executable ran.
The tracked `bin/git` header is a source-only example, not runtime evidence.
The focused tests reject ten malformed or unsupported examples.
A `not_script` result only says the supplied bytes lack a shebang. It is not
a native-binary identity or trust decision. Future readers must bind bounded
bytes to a stable selected file without following unreviewed links.

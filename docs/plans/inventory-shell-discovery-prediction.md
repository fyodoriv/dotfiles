# Shell source discovery prediction

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The committed-tree and review-ledger checks do not independently discover
embedded programs or generated outputs.

**Hypothesis:** Reusing `shfmt` to parse committed shell source can identify
static interpreter bodies and possible generated outputs without executing
the source. Dynamic or unsupported forms remain explicitly unresolved.

**Measurement:** Hosted controls parse fixed shell fixtures containing
heredoc and inline interpreter programs, generated-file redirections, dynamic
commands, and malformed syntax. A hosted integration check scans a committed
tracked shell file. Source text stays in process memory and is not logged.

**Success:** Every planted static boundary is reported, every planted dynamic
or unsupported case is unresolved, and no source program executes. **Pivot:**
Any missed planted boundary or silent parse failure rejects the scanner.

This covers only parsed shell sources. Other languages, template syntax,
dynamic targets, uncommitted work, and human review remain open. It cannot by
itself make `migration-check inventory --check` pass.

**Anchor:** `rust-source-inventory`; the existing `shfmt` parser; Basili,
Caldiera, Rombach 1994; Munafò et al. 2017.

# OpenCode helper boundary

Register this review before the detailed source trace. An exploratory search
found the version helper in the LaunchAgent template, a CLI wrapper, a doctor
module and tests. A name search does not establish complete caller coverage.

- **Hypothesis:** A pinned source review can bind the helper and four observed
  caller categories to their declared resolution and invocation boundaries,
  while leaving dynamic selection and unknown callers unresolved.
- **Measurement:** Inspect source at commit
  `d6e4e4acc9e9e0ca2658b2875100316780c4b95b` with `git show` and a bounded
  tracked-source search. Record each source blob, exact line range, declared
  action and conditions. Verify identities and anchors against that commit.
- **Success:** Four of four observed caller categories and the helper have
  pinned source evidence or an explicit unresolved status; zero runtime
  execution, installed-binary identity or complete caller coverage claims.
- **Pivot:** A missing, ambiguous or changed source anchor remains unresolved.
  Do not infer that the selected executable is the installed binary or that a
  source-declared branch ran.
- **Anchor:** [lifecycle reconciliation](current-lifecycle-reconciliation.md),
  Basili, Caldiera and Rombach (1994), Goal Question Metric.

The review does not execute the helper, agent or tests. It does not qualify
the shared validator, generated output, or the migration audit.

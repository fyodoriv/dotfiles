# Read-only runner reference prediction

Registered before the fix on 2026-11-13. The heavy-run hook refuses a runner
lookup lifted from command substitution even when a narrow read-only search
uses its output only as a file path. The task is
`heavy-run-read-only-reference`.

- **Hypothesis:** Recognizing only a complete, literal `rg` file-inspection
  command with a literal `command -v bats` substitution removes this false
  block without permitting a runner invocation.
- **Measurement:** Add focused synthetic JSON-input controls to
  `tests/agent-hooks-heavy-build-callers.bats`; run the added cases and the
  existing caller suite with `heavy-run bats tests/agent-hooks-heavy-build-callers.bats`
  and hosted CI. Confirm the planted read-only case fails before the fix.
- **Success:** At least three literal file-inspection forms pass, at least
  three actual unqueued heavy commands remain blocked, and zero planted
  substitution, pipeline, unapproved chained command, shell-expansion, `rg --pre`,
  redirection or executable-position bypasses pass. Synthetic command payloads
  are data and must never dispatch the runner.
- **Pivot:** If the complete input cannot be recognized without shell parsing
  ambiguity, or any planted heavy bypass passes, keep the existing fail-closed
  guard and record the counterexample.
- **Anchor:** The task and existing `_lookup_only` and `_strip_text` behavior;
  Basili et al. 1994 (GQM) and Munafò et al. 2017 (preregistration).

The allowance applies only to a whole top-level command: an optional exact
`command -v bats &&` prefix, literal `rg`, an optional `-n` or `-l`, one
single-quoted simple search term, and the exact double-quoted
`$(command -v bats)` file argument. Anchor both ends and permit only spaces
and tabs, never newlines. Check the original complete command before splitting. Except for that exact optional prefix, no shell operator, extra argument, variable, backtick, backslash, quote breakout, comment,
assignment, flag with code execution, or output redirection is accepted.
Plant each as a refusal control, including a nested substitution, trailing
operator, alias/function declaration, newline and `rg --pre`. The lexical
check relies on the existing trusted shell and PATH assumption; it cannot
prove what a redefined `rg` or `command` executes. This deliberately leaves other read-only
forms blocked. It does not change queue rules or execute a payload during
tests.

The exact historical input was not retained in this task record. The paired
lookup-and-search fixture reproduces the recorded shape, not the original
bytes. Do not claim the original incident is reproduced without that receipt.

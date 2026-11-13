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

The rejected first allowance applied only to a whole top-level command: an optional exact
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

## Rejected first candidate and superseded prediction

The prediction in this section was superseded by the final prediction below.
The first candidate passed the three read-only fixtures and 84 caller tests,
but independent review found that inherited ripgrep configuration can enable
a preprocessor. It is rejected and removed. [Ripgrep's guide](https://github.com/BurntSushi/ripgrep/blob/master/GUIDE.md#configuration-file)
documents `RIPGREP_CONFIG_PATH` and `--no-config`; its [changelog](https://github.com/BurntSushi/ripgrep/blob/master/CHANGELOG.md)
documents `--pre`. The old search without `--no-config` stays blocked.

- **Hypothesis:** Requiring literal `rg --no-config` in the same closed
  command grammar admits a safe explicit alternative while retaining the
  existing block for the original form and all planted bypasses.
- **Measurement:** First use a trusted resolved `rg`, private scratch HOME and TMPDIR, an
  owned regular file and an absolute executable scratch preprocessor that
  writes only a scratch canary. Verify configured ripgrep invokes it and
  `--no-config` does not, with matching output and successful exits in both
  runs. Add focused hook cases for three `--no-config`
  variants, the old form, an explicit `--pre` option, a synthetic configured
  preprocessor, and the original adversarial matrix. Run the affected Bats file with `heavy-run`
  and hosted CI.
- **Success:** The synthetic preprocessor canary appears only for the
  configured run without `--no-config`; all three exact safe alternatives
  pass the hook, the old form and all planted unsafe inputs refuse, and no
  hook fixture dispatches a runner.
- **Pivot:** A missing or unexpected canary, a bypass, ambiguous effective
  tool identity, or altered legacy guard result rejects this method. Preserve
  the old guard and record the limitation.
- **Scope:** This is a safe alternative, not a fix for every original
  read-only command. Shell command substitution strips trailing newlines
  before the hook matches; do not claim it rejects those normalized bytes.
  Other shell/PATH trust assumptions remain as stated above.

Anchor: ripgrep's guide and changelog above, the task, and the independent
review on 2026-11-13.

## Rejected option parsing and final prediction

The `--no-config` candidate passed the focused controls, but independent
review found that a quoted search term beginning with `-` can still be an
option. That candidate is removed. The proposed alternative now requires an
explicit `--` before the quoted term. The earlier `--no-config` form without
`--` stays blocked.

- **Hypothesis:** The explicit end-of-options marker makes the literal term
  an operand while retaining the no-configuration boundary and all prior
  refusal controls.
- **Measurement:** Repeat the scratch preprocessor canary and use a scratch
  file containing `--passthru` to check `rg --no-config --` treats it as the
  pattern. Add hook controls for the exact new form, the prior form without
  `--`, `--passthru` without `--`, explicit `--pre`, and the existing unsafe
  matrix. Run `heavy-run bats tests/agent-hooks-heavy-build-callers.bats` and
  hosted CI; no user files or programs are involved.
- **Success:** The three exact new search forms pass, including an option-like
  term after `--`; the scratch match succeeds, both earlier forms and every
  unsafe mutation refuse, and no hook fixture dispatches a runner.
- **Pivot:** Any option parsing surprise, bypass, canary failure, or guard
  regression rejects the method and preserves the original guard.
- **Anchor:** The preceding pivot and independent review on 2026-11-13;
  Basili et al. 1994 (GQM) and Munafò et al. 2017 (preregistration).

This remains a narrow explicit workaround. It does not admit the original
command, prove arbitrary shell safety, or establish the identity of a
replaced executable, function or alias.

## Final focused result (2026-11-13)

The exact new search form was blocked before the change (expected 0, received
2). The scratch preprocessor and option-like pattern controls passed. After
the change, the focused caller file passed all 86 tests, including the four
explicit alternatives, the earlier blocked forms and the unsafe-input matrix.
Independent review found no remaining matcher bypass within the documented
trusted shell and PATH boundary. The original command form still refuses; the
related task remains open. Hosted CI is required for the final branch.

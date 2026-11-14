# Hook status shortcut: bounded trial

Register before implementation. Reuse the narrow literal `git status` shortcut
from draft pull request 621, without its experimental measurement harness.
Unknown syntax keeps the existing guard. The heavy-run hook is unchanged.

- **Hypothesis:** The shortcut preserves the guard's verdict and output for
  the existing and added safety cases and cuts its registered status-row time.
- **Measurement:** Hosted macOS runs the existing hook suite, targeted status
  and hostile-syntax parity cases, and the unchanged performance gate against
  the current default branch. The gate reports the existing status row.
- **Success:** Zero changed verdicts or output in the controlled parity cases,
  zero false permits, and a `hook-block-dangerous-git` ratio at most 0.50.
  The remaining hook and gate G memory limit stay open.
- **Pivot:** Any mismatch, missing measurement, or missed ratio retains the
  existing guard. A passing case does not qualify the second hook.
- **Anchor:** The [migration plan](rust-migration.md), the existing
  [hook baseline](rust-hook-baseline-2026-11-11.md), and the narrower source
  changes in [draft pull request 621](https://github.com/fyodoriv/dotfiles/pull/621).

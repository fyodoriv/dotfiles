# Report a managed-file comparison failure

[Issue #731](https://github.com/fyodoriv/dotfiles/issues/731) asks
what led to the generic managed-file result. Doctor currently uses
the same failure result for a real difference and a comparator that
failed before returning a usable result.

- **Hypothesis**: Doctor reports the comparator's exit code when it
  cannot check an existing regular file. A successful comparison with
  a real difference keeps the current managed-file result.
- **Measurement**: Run hosted `bats tests/doctor.bats`. Extend the
  existing disposable managed-file fixture. Make its comparison
  wrapper return 65 with a synthetic private marker in standard error.
  Observe the JSON failure and normal text. Keep the real 022 pass,
  queue pass and 077 mode-only difference as compatibility controls.
- **Success**: The one comparator failure reports exit 65 in both
  outputs with 0 private markers. Both healthy cases and the ordinary
  difference keep their current result. All four keep the file intact.
- **Pivot**: One changed ordinary result, one missing exit code,
  one printed marker or one file mutation rejects the patch.
- **Anchor**: Issue #731, the `check_managed` entry point, and the
  existing [caller-mask fixture](managed-file-caller-mask.md).

The comparison error helps explain a future run. The exact old
full-audit observation still needs direct evidence.

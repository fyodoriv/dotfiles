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

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44874112993/job/136754897956)
returned the generic managed-file JSON result with exit 65 missing.
The real 022 and 077 controls completed before the failing assertion.

The [first candidate](https://github.com/fyodoriv/dotfiles/actions/runs/44874467181/job/136755998974)
passed the real Doctor checks. The existing failure-line check rejected
its plain-text hint because that line lacked the expected `fix:` label.
Use the existing label and keep the safe comparison exit code.

## Leave a file in place after a failed comparison

- **Hypothesis**: Doctor can report a failed comparison in repair
  mode without applying a file it could not inspect. It still repairs
  a confirmed difference.
- **Measurement**: Run hosted `bats tests/doctor.bats` with the
  disposable editor file. Simulate comparison exit 65 with a private
  stderr marker. Record each apply attempt in a scratch canary.
  In a separate comparison, change the file and allow its synthetic
  apply. Check text, JSON, exit code, bytes and mode.
- **Success**: A failed comparison makes 0 apply attempts in either
  output mode and preserves the file. Text and JSON report exit 65
  without the marker. A confirmed difference makes 1 apply attempt
  and the repair recheck passes.
- **Pivot**: Stop for 1 apply after failed comparison, disclosure,
  changed target on refusal or broken repair of a confirmed difference.
- **Anchor**: Issue #731 and the comparison and repair checks in
  `bin/dotfiles-doctor`.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44892073205/job/136809877320)
repaired the confirmed difference, then attempted to apply an
existing file after the comparator failed. The repair branch ran
before the exit-code check. Report the comparison failure before
considering repair.

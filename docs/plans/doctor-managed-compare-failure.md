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

The [first candidate](https://github.com/fyodoriv/dotfiles/actions/runs/44892310701/job/136810576321)
passed the real chezmoi comparison and repair controls. An older
verification fixture returned plain `diff`'s exit 1 for a normal
difference. A disposable built-in `chezmoi diff` returned exit 0
and the difference while leaving its target untouched. Align the
fixture with that contract and keep the separate unreadable case.

## Report a stale chezmoi config template once

A disposable chezmoi setup compared one unchanged target before
and after changing its config template. Both comparisons exited
zero. Only the stale comparison wrote the template warning.
The built-in doctor and source-path commands omitted the warning.

- **Hypothesis**: Dotfiles Doctor can report the known stale-template
  warning once per invocation without changing its managed-file results.
- **Measurement**: Run hosted `bats tests/doctor.bats`. Use two
  comparisons in a disposable module. Add the stale-template warning
  and an unrelated synthetic private marker to comparator stderr.
  Check text, JSON and a separate control with only the unrelated marker.
- **Success**: 1 fixed advisory in each stale run, 0 advisories in the
  unrelated control, 0 private markers printed and 0 apply attempts.
  Both managed-file results stay healthy and exit status stays zero.
- **Pivot**: At least 1 duplicate, missed or false advisory, printed
  marker, file change or failed ordinary comparison rejects it.
- **Anchor**: Issue #731, the ordinary zero-exit comparison result,
  and the existing Doctor advisory output.

Sample the first successful comparison of an existing file. The
applied source and config stay common across the checks within one
invocation. Keep the comparison and warning results separate.

Hosted [baseline run](https://github.com/fyodoriv/dotfiles/actions/runs/44896501565/job/136823187645)
fails at the stale JSON assertion. The unrelated warning control
passes. The missing advisory is the first stale-run failure.

The comparison opens a private empty file and unlinks it before
running chezmoi. Doctor recognizes only the known warning line.
If sample setup fails, Doctor uses the ordinary comparison. A
separate canary catches attempts to regenerate config in repair mode.

## Compare every affected managed check in a full audit

- **Hypothesis**: The queue preserves all ten managed-file results
  reported in issue #731 when Doctor checks every module.
- **Measurement**: Run hosted `bats tests/doctor.bats` on macOS.
  Use the actual managed-check declarations with matching disposable
  files and real chezmoi comparisons. Compare one full Doctor audit
  through heavy-run with each individual module. Run the full audit
  separately with the old restrictive caller mask as a negative control.
- **Success**: All 10 checks pass in both routes under caller mask
  `022`, all 10 fail in the restrictive control, and no fixture
  comparison runs a repair or changes a target.
- **Pivot**: At least 1 missing, mismatched or unexamined result,
  unexpected repair or changed target rejects issue closure.
- **Anchor**: [Issue #731 and its root-cause report](https://github.com/fyodoriv/dotfiles/issues/731)
  and the [heavy-run caller mask fix](https://github.com/fyodoriv/dotfiles/pull/756).

The fixture covers the managed checks named in the report. It runs the
real Doctor module selection and chezmoi comparison in a disposable home.
Unrelated local application checks and settings are outside the fixture.

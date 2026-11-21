# Non-interactive AC timer repair

[Issue #572](https://github.com/fyodoriv/dotfiles/issues/572) recorded a
scheduled doctor run stuck at a password prompt. The AC timer repair
runs plain `sudo`. The doctor's time limit cannot reliably end that
privileged process. Reuse the non-interactive invocation from the macOS
doctor module.

- **Hypothesis**: The AC timer repair returns promptly without a
  terminal or cached credentials, reports that it needs sudo, and
  still checks the setting again after a successful repair.
- **Measurement**: Run hosted `bats tests/module-resilience.bats`.
  Run the real doctor with its AC timer check, standard input closed,
  and fake sudo and pmset commands. Measure the no-credential run
  against a 5-second limit and record the exact repair attempts. Run
  a second case that grants the fake command access and changes the
  fake timer settings.
- **Success**: In the no-credential case, 1 non-interactive attempt,
  0 interactive attempts, 0 setting writes, and status `fail` with
  a sudo hint within 5 seconds. With access, 1 non-interactive attempt,
  1 setting write, and status `fixed` after the settings check.
- **Pivot**: Any interactive attempt, unexpected write, incorrect
  result, or no-credential run at or above 5 seconds rejects the change.
- **Anchor**: Issue #572 and the `sudo -n pmset` repairs in
  `modules/macos/doctor.sh`.

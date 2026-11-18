# Match the telemetry prompt to the off policy

When a valid telemetry policy turns all reporting off, status can
still tell a person with no recorded answer to turn reporting on.

- **Hypothesis**: Status can explain the off policy without offering
  a command that cannot enable it.
- **Measurement**: Run the focused telemetry sink status test on
  hosted CI. Compare an unset answer with no policy, an unset answer
  with the off policy, and a recorded yes with the off policy.
- **Success**: Zero enable suggestions under the off policy, the
  existing prompt with no policy, the recorded answer still shown,
  zero requests, and identical recorded state after status.
- **Pivot**: An enable suggestion, lost recorded answer, changed
  state or network request rejects the fix.
- **Anchor**: [Dotfiles issue #729](https://github.com/fyodoriv/dotfiles/issues/729)
  and the [telemetry status contract](../observability.md).

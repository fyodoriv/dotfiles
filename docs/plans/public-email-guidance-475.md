# Public-safe Git email guidance (#475)

## Prediction before implementation

Goal: make the public-safe email failure actionable without guessing or
changing a person's identity. Question: does the check ask the person to
choose a safe email while leaving both Git configuration and the privacy
guard unchanged?

Measurement: add `tests/git-doctor-public-email-guidance.bats`, reproduce the
failure on the existing check, then run:

```sh
heavy-run bats tests/git-doctor-public-email-guidance.bats tests/git-doctor-email-allowance.bats
heavy-run make check
```

Use an isolated Git repository and a synthetic private-email pattern. The
failed check must remain a failure, must not expose the email, and must have
no executable automatic fix. It must tell the person to review the repo's
effective Git identity and choose their own public-safe email, then show the
repo-local action `git -C <checked-checkout> config --local user.email "YOUR
PUBLIC EMAIL"`. The checked path must be shell-quoted so paths with spaces
work; it must be the same checkout the check reads, not the caller's current
repository. The person chooses the value and initiates the change.

Test conflicting effective identities both ways: a private local email with a
safe global email must fail, and a safe local email with a private global
email must pass. Cover normal and JSON output. Neither the synthetic private
email nor its pattern may appear in output or fix metadata. Hash both local
and global config before and after normal and `--fix` runs; neither may be
changed by the isolated check. A passing check keeps its existing description.

Success is 1/1 actionable failure, 1/1 unchanged passing check, no identity
write or email disclosure in the isolated tests, and all listed checks
passing. Any missing guidance, write, disclosure, changed pass behavior or
failed gate abandons this approach. This is one human-only case within #475,
not a claim that the entire issue is complete.

Anchor: [Goal Question Metric](https://doi.org/10.1002/9780470172669.ch12).

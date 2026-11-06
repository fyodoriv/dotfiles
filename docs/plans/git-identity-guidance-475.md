# Git identity doctor guidance (#475)

## Prediction before implementation

Goal: let a person resolve missing Git identity without an agent guessing it.
Question: do the three Git identity failures name the owner and a concrete
action, while passing checks remain concise and no identity is written?

Measurement: add `tests/git-doctor-identity-guidance.bats` with an isolated
home and synthetic identity, then run:

```sh
heavy-run bats tests/git-doctor-identity-guidance.bats tests/git-doctor-email-allowance.bats
heavy-run make check
```

Before changing the module, confirm the guidance test fails. The missing-file,
missing-name and missing-email checks must remain failures and must not expose
an automatic fix. Failure text in both normal and JSON output must tell the
person to choose their own identity. For a missing file, tell them to copy
the existing example without overwriting a file, then edit its placeholders.
For a missing effective name or email, tell them to inspect existing Git
configuration and add or correct the chosen value in `~/.gitconfig.local`;
do not imply that Git reads only that file or direct an unconditional overwrite.
Use these actions:

- Missing file: run `cp -n "$(chezmoi source-path)/gitconfig.local.example" "$HOME/.gitconfig.local"`, then edit the example name and email.
- Missing effective name: inspect Git configuration and the local file; if
  `user.name` is absent there, add the person's chosen name with
  `git config --file "$HOME/.gitconfig.local" --add user.name "YOUR NAME"`.
  If a value exists, the person corrects it themselves. Ensure Git includes
  that file.
- Missing effective email: follow the same steps for `user.email`, using
  `git config --file "$HOME/.gitconfig.local" --add user.email "YOUR EMAIL"`.

Success is 3/3 failed checks naming the person and the specific next action,
3/3 passing checks retaining their existing descriptions, and no identity file
created by a read-only doctor run. Tests must cover absent and partial files,
preserve existing values, and prove that `--fix` does not write identity using
an isolated module fixture containing only these checks. All listed tests and
the repository gate must pass. Fewer than 3/3 actionable failures or any
changed pass/automatic-write behavior abandons this approach.

This is a narrow part of #475. It does not claim that every fresh-Mac doctor
failure is actionable. Anchor: [Goal Question Metric](https://doi.org/10.1002/9780470172669.ch12).

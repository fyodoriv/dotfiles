# Explain the Python framework repair a user can run

[Issue #577](https://github.com/fyodoriv/dotfiles/issues/577) reports
that Doctor points users without admin rights to an admin repair.
The installer tool also reports paths from logs and saved environments,
which can remain after a successful user repair.

- **Hypothesis**: A named user-only mode lets a user finish the
  existing fallback without a sudo call. Keep active framework
  dependencies visible and omit dormant logs and backups.
- **Measurement**: Run hosted Bats with a disposable home, a
  fake framework tree and inert command fixtures. Observe sudo
  invocations, the selected Python provider and the reported paths.
  Exercise Doctor's framework check with the original framework
  in place and no active framework-based virtual environment.
- **Success**: 0 sudo calls in user-only mode, 0 invocations of
  the framework interpreter, 0 reported log or backup paths, and
  1 reported active config path in the mixed fixture. The Doctor
  framework notice stays advisory and names the user and admin options.
- **Pivot**: Any missed active config, wrong severity or implicit
  sudo or interpreter invocation rejects the candidate.
- **Anchor**: Issue #577 and the existing user-mode fallback in
  `bin/dotfiles-remove-framework-python`.

The hosted fixtures use no real sudo, framework executable, or
LaunchAgent. The system framework still needs a separate admin action.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44878698797/job/136769013126)
recorded one invocation of the framework-side Python and one sudo call.
Doctor's advisory also lacked the user-only route. The command ignored
the new mode and probed the first Python on PATH before checking sudo.

## Reject unknown options and report incomplete pipx repair

- **Hypothesis**: A misspelled option leaves the profile and repair
  commands untouched. A failed reinstall reports the affected pipx
  environment and a nonzero status.
- **Measurement**: Run the hosted mixed-path fixture with a misspelled
  option. Run a separate fixture with one framework-based pipx
  environment and a failing reinstall.
- **Success**: The invalid option exits 2 with zero repair calls and
  no profile changes. The failed reinstall exits 1, makes one
  reinstall attempt, and names the environment that could not be repaired.
- **Pivot**: Any invalid-option write or false-success message
  rejects the candidate.
- **Anchor**: The command entry point and existing pipx repair loop.

The [hosted follow-up](https://github.com/fyodoriv/dotfiles/actions/runs/44879011870/job/136770052909)
returned 0 for both the invalid option and the failed reinstall.
The new advisory, no-sudo path, and active-config scan reached their
expected results before the invalid-option assertion.

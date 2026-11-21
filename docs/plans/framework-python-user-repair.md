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

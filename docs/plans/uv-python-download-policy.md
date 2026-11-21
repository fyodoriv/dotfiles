# Opt in to blocking automatic uv Python downloads

[Issue #634](https://github.com/fyodoriv/dotfiles/issues/634) reports
that unattended downloads can put a new interpreter on disk before
the endpoint signing pass. The owner can opt in to using installed
Python versions while choosing when to add a new one.

- **Hypothesis**: With the optional download setting enabled, the
  scheduled upgrade and both apply-time Python installers leave the
  existing interpreters in place. The scheduled tool upgrade remains
  available.
- **Measurement**: Run hosted fixtures with the setting on and off.
  Render the actual Topgrade configuration and both installer paths.
  Observe fake uv argv and its download policy, then verify an
  already-installed interpreter and the missing-interpreter result.
  Exercise the user config creation and Doctor validation in a
  disposable home.
- **Success**: 0 automatic Python installs or upgrades with the policy
  on, 1 tool upgrade with downloads disabled, 1 correct missing-Python
  hint, 1 passing existing-interpreter case and 0 overwritten user
  config files. The false/default setting keeps all prior operations.
- **Pivot**: Any download request in the enabled fixtures, any missed
  tool upgrade, a wrong Doctor result, or a changed default rejects
  the candidate.
- **Anchor**: Issue #634, [uv's download policy](https://docs.astral.sh/uv/reference/settings/#python-downloads),
  and [Topgrade's uv step](https://github.com/topgrade-rs/topgrade/blob/v17.16.0/src/steps/generic.rs#L2267).

Use a distinct opt-in so current endpoint-hardening users can still
finish a first setup. Keep a pre-existing user uv configuration and
report its policy if it does not match the opt-in. Automatic Dotfiles
paths apply the policy for their own subprocesses. Keep ordinary
standalone project and user overrides under the program's normal
precedence. Do not download or sign a real interpreter in these tests.

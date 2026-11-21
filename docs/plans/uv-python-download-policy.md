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

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44876768131/job/136763068333)
passed both default cases. The enabled Topgrade template still had its
combined uv step. The standalone installer and local-LLM resolver also
missed the expected enabled-policy behavior.

## Check the rest of each unattended entry point

Review found a Poetry repair behind scheduled Doctor, a caller that
captures its interpreter result, and the custom user config location.

- **Hypothesis**: With the policy on and no installed interpreter,
  Poetry repair leaves both original paths intact. The full rendered
  local-LLM installer stops before pipx or model operations. A
  custom configuration directory stays owner-managed.
- **Measurement**: Extend the hosted policy fixtures with an absent
  interpreter and inert executables. Call the existing Poetry repair
  helper, and run the complete rendered local-LLM script with its
  sentinel present. Run real chezmoi against a disposable home whose
  XDG config directory differs from the default.
- **Success**: 0 moved paths or tool installs without Python, 0 pipx
  or model requests, and 0 user files created at the unused default
  location. The installed-interpreter Poetry control runs 1 tool
  install with downloads disabled. Doctor checks the selected config.
- **Pivot**: One tool call without a usable interpreter, an unexpected
  backup, one changed user config, or one misleading check rejects.
- **Anchor**: The scheduled Doctor and Poetry repair call sites,
  the local-LLM caller, and [uv configuration precedence](https://docs.astral.sh/uv/concepts/configuration-files/).

The [second hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44877551957/job/136765582899)
called pipx with no usable Python and let the Poetry repair return 0.
The two apply fixtures also failed because their scratch config lacked
the required profile. After adding the profile to the scratch config,
a direct chezmoi probe showed that apply created the unused default
config when the custom config directory was active.

## Defer unattended Poetry migration with the policy on

- **Hypothesis**: Keep the original Poetry paths when downloads are
  disabled, even if a project interpreter is available. Keep the
  ordinary automatic repair with the policy off.
- **Measurement**: Run the hosted repair fixture with an installed
  interpreter and a simulated tool-install refusal. Run the same
  helper with the policy off and an available tool install.
- **Success**: 0 uv calls and 0 moved paths with the policy on.
  With the policy off, 2 saved paths and 1 ordinary tool install.
- **Pivot**: Any altered path or uv call with the policy enabled,
  or a failed ordinary repair, rejects the change.
- **Anchor**: [uv tool interpreter selection](https://docs.astral.sh/uv/concepts/tools/#python-versions).

A generic Python lookup can accept a project interpreter that tool
installation ignores. Defer the migration with the policy enabled
because the existing repair moves both paths before it installs the tool.

# Keep the guard on read-only branch checks

Registered on 2026-11-20. Target: `1d56a3fd`. Related report: [#761](https://github.com/fyodoriv/dotfiles/issues/761).

- **Hypothesis**: Accepting a single-quoted branch name in the existing exact read-only comparison cuts the incorrect refusals in the two registered cases from 2 to 0.
- **Measurement**: Run `bats tests/agent-hooks-block-dangerous-git.bats` on the hosted Mac before and after the fix. Compare the hook decisions for literal operands with a later read-only command and for the existing refusal controls. The fixture never executes the command input.
- **Success**: Allow 2 of 2 quoted branch names and keep all existing decisions. Refuse every new unsafe or unsupported control, including expansion and a later destructive command.
- **Pivot**: Stop after 1 incorrect allowance, 1 refusal of a registered benign comparison, 1 changed original decision, or 1 command input executed.
- **Anchor**: [Dotfiles report #761](https://github.com/fyodoriv/dotfiles/issues/761) and the existing exact comparison in `agent-hooks/block-dangerous-git.sh`.

The scope is the leading read-only comparison with a literal branch name. The guard still checks the remainder of the input.

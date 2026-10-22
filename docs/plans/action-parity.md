# Plan: every dotfiles action runs through the CLI and agents

- **Task**: action-parity
- **Status**: implemented 2026-10-22

## Goal

The owner's rule "Every action through CLI, agent, and UI, with tests": one
generated action list, so no command is reachable from only one path.
dotfiles has no UI (no web app or window), so parity covers the CLI and
agents. A UI would read the same list.

## Design

- One source, nothing listed twice. `bin/dotfiles-actions` reads
  `bin/dotfiles` itself:
  - the names and aliases from the dispatch `case` arms;
  - the usage forms, arguments, and what each one does from the `show_help`
    text (one line per form: the usage, two or more spaces, the description);
  - the notes from four-space comments in an arm: `# terminal-only: <why>`,
    `# confirm: <what it changes>`, `# agent: <what to do differently>`.
- `dotfiles actions [<name>] [--json]` prints the list; agents use `--json`
  (name, aliases, command, help, forms with usage and parsed arguments,
  `agent`, `terminal_only`, `confirm`, `agent_note`). `/dotfiles`
  (`commands/dotfiles.md`) points agents at it instead of `--help`.
- `dotfiles actions --check` fails when a dispatched command has no help line,
  a help line names no command, or a help line has no description.
- It reads files only (awk and jq, both on a new Mac): no git, no network, no
  update check. BWK awk with Apple jq and GNU awk with Homebrew jq give the
  same JSON.
- Terminal-only: `edit` (an editor), `quickstart` (a y/N wizard), `leak` (a
  person-only bypass). Confirm: `apply`, `init`, `update`, `upgrade`, `sync`,
  `install`, `uninstall`, `contribute`, `plugin`. The commands that prompt
  (`uninstall`, `install run`, the start screen) take `--yes`.

## Measurement

`tests/dotfiles-actions.bats` (run by `make check` when `bin/dotfiles`
changes): the count of dispatched commands missing from
`dotfiles actions --json` or from the help text.

- Baseline 2026-10-22: 35 of 35 dispatched names had no agent catalog entry
  (`dotfiles actions` was "Unknown command"), and 3 (`plugin`, `leak`,
  `memory`) had no line in `dotfiles --help`, the only list agents had.
- Success: 0 missing, enforced by the test in the gate.
- Pivot: if the dispatch could not be parsed, keep one registry file that
  both the dispatch and `actions` read, never two lists.

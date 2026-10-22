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

## Follow-up: review of PR #277

- Arms are read by case depth, not by indent: an arm is the first code after
  `in` or after `;;` at depth 1, at any indent, with any spaces around `|`.
  The test reads the arms with bash's own parser (`declare -f` of the
  dispatch block), so the generator and the test cannot miss the same arm.
- `subforms` come from the "Usage:" header of the script an arm runs (for
  example `dotfiles config get <key>`, `dotfiles plugin update`).
- A usage that runs into its description (one space, then a capital or a
  bare word after the first `[`, `<`, or `--`) fails `--check`, in the help
  text and in script headers.
- Each `confirm` action takes `--yes` or has an `# unattended:` reason, and
  `--check` fails otherwise. `contribute` (a public PR), `init`, and `update`
  now ask y/N at a terminal and refuse without one unless `--yes`
  (`lib/confirm.sh`; `--dry-run` and `--help` need no yes). Nothing runs
  `dotfiles update` unattended, so it got a real gate. `apply`, `sync`, and
  `upgrade` keep running unattended: the update-tooling and tooling-checkup
  skills, `com.dotfiles.dotfiles-sync`, and `com.dotfiles.dotfiles-upgrade`
  run them, and their notes say so.
- The README CLI reference must name every action (a test).

## Follow-up: cheat and the start screen (task cheat-reads-dotfiles-actions)

- `cheat` kept its own hand-written list of `dotfiles` commands, and the start
  screen footer pointed at `dotfiles --help`. Both now point at the generated
  list: the "dotfiles (from dotfiles actions)" section of `cheat` comes from
  `dotfiles actions --json`, one line per usage form, and the footer says
  `All commands: dotfiles actions`. What a form does is cut to its first
  sentence; while that is over 60 characters, the last `; ` point goes, then a
  trailing `(...)`, then it is cut at a word.
- Without jq, or when `dotfiles actions` fails, `cheat` reads the `show_help`
  text in `bin/dotfiles` directly and says why the list is plain. It stays
  offline: `dotfiles actions` reads files only.
- The `chezmoi` lines stay hand-written: they are chezmoi's own commands, not
  dotfiles actions. `dotfiles-stats` and `dotfiles-sync` are gone from the
  list; `dotfiles stats` and `dotfiles sync` run them.
- Measurement: actions in `dotfiles actions --json` whose name has no
  `dotfiles <name>` (or `dotfiles --<name>`) line in `cheat`.
  Baseline 2026-10-22: 25 of 36 (help, actions, version, apply, init, diff,
  plugin, validate, leak, sync, edit, cd, update, managed, status, stats,
  install, metrics, contribute, cheat, defaults-add, defaults-preview,
  quickstart, upgrade, memory). After: 0 of 36. `tests/cheat.bats` checks the
  stricter form: a row for the first usage of each action. On the old `cheat`
  it reports 36 of 36 missing. It runs in `make check` (bin/bats-affected
  selects it when `bin/cheat`, `bin/dotfiles`, or `bin/dotfiles-actions`
  changes), also without jq (with macOS awk), for a new command added to
  `bin/dotfiles`, and for a help line with no description.
- Cost: `cheat` with no topic went from about 0.03 s to about 0.25 s at load
  220 on 10 cores (the `dotfiles actions --json` run). `cheat git` and the
  other topics except `shell` do not run it.

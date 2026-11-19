# Keep the opted-in Git guard across child shells

## Registered experiment

Goal: preserve an already active, managed Agentbrew Git guard when a
Dotfiles child shell starts. Question: can shell startup retain the
first Git wrapper while the Dotfiles wrapper still reaches Git exactly
once? Metrics: executable selection, inherited path, and probe calls.

Hypothesis: startup currently puts Dotfiles first, even when the home
Agentbrew guard is at the front. Preserve that exact front entry. When
the system Git probe fails, skip the guard while looking for the real
Git binary.

Measurement: run the added startup and fallback controls in
`tests/git-wrapper.bats` on hosted CI. Render the shell template with
scratch paths and use executable recorders for the guard and fallback
Git. Check a normal, non-opted-in startup as a control.

Success: all three controls pass. The opted-in startup retains the guard.
The normal startup keeps Dotfiles first. The fallback reaches the
external Git once for the original read-only command and calls the
Agentbrew guard zero times.

Pivot: any new PATH entry without an already active managed guard, any
probe of the Agentbrew wrapper, or a failure in the existing Git policy
checks rejects the change.

Anchor: `dot_config/dotfiles/bash-env.sh.tmpl`, `bin/git`, and the
[Claude Code session environment contract](https://code.claude.com/docs/en/hooks#persist-environment-variables).

## Baseline

The hosted Mac run for `2bcbe8af` passed ordinary startup and failed
the two registered opt-in controls. Shell startup selected the Dotfiles
wrapper before the managed guard. The fallback searched the guard
before the expected Git candidate. The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44626058363)
records both failed expectations.

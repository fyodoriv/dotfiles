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

## Claude command rewrite prediction

The command rewrite hook emits a fixed PATH. A Claude Bash command can
lose its guard if that rewrite places Dotfiles first after the session
environment is loaded. The session can carry a marker for the exact
managed guard independently of PATH. The Dotfiles Git wrapper can ask
that guard for a decision before it runs the ordinary Git command.

Measurement: use the default Claude PreToolUse envelope and a scratch
session environment. Run the rewritten command with a Git recorder.
Exercise the fixed PATH with and without the opted-in session marker.

Success: a supported refused request reaches Git zero times. An ordinary
request reaches Git once with the original arguments. An unopted shell
uses its ordinary Git path and does not call the guard.

Pivot: any changed command arguments, duplicate delegate, guard invocation
outside an opted-in session, or failure of the existing fixed-PATH
controls rejects this design.

Anchor: `agent-hooks/prepend-endpoint-path.sh`, the managed Git wrapper,
and the Claude session environment contract above.

The [hosted rewrite control](https://github.com/fyodoriv/dotfiles/actions/runs/44629793792)
passed the repaired startup and fallback cases. It then failed the new
Claude rewrite control. The composed scratch session observed exit 0
and a Git recorder call where the expected outcome was exit 2 with zero
calls.

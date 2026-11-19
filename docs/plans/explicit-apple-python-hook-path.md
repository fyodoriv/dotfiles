# Preserve explicit Apple Python paths in agent commands

## Registered experiment

Goal: keep the interpreter choice that an agent command states and keep draft text intact. Question: can the path hook still prepare its environment without replacing explicit Python paths? Metric: command suffixes that change in the three synthetic hook inputs.

Hypothesis: removing Python from the two path substitutions reduces three unintended changes to zero. A bare command still receives the managed PATH and existing curl substitutions still pass.

Measurement: send an explicit `/usr/bin/python3` command, an explicit `/usr/bin/python3.13` command, and a heredoc with both paths through the real hook. Compare the exact command after the managed PATH prefix. Run these cases on hosted CI against the old behavior first. Then run the same cases and the required full gate with the correction.

Success: zero changed command suffixes out of three, zero interpreter launches in the controls, and all required hosted checks pass.

Pivot: any remaining substitution, lost managed PATH, failed curl control, or required check failure rejects the change. A missing versioned interpreter is outside this command-choice check.

Anchor: [Dotfiles issue #784](https://github.com/fyodoriv/dotfiles/issues/784) and Basili, Caldiera and Rombach (1994), Goal Question Metric.

The controls use synthetic command text and never run it. The selected command path is independent of bare-name lookup and endpoint approval on a managed machine.

## Baseline

Prediction commit `1367e325` preceded the controls. The original hook failed
all three exact command checks in the [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44597738094/job/135820481665)
at `tests/agent-hooks-prepend-endpoint-path.bats:119`. The direct control
also observed three changed commands. The curl and bare-name controls passed.

# Observe the project cap before asserting it

## Registered experiment

Goal: protect the project cap with a repeatable queue test. Question: can the fixture observe the final project-cap reason after a short safety hold? Metric: failed observations and commands that start before their project releases a slot.

Hypothesis: use the existing 50 polls at 100 ms to observe the exact project-cap reason. This reduces early observations from one to zero in a control that briefly holds a slot without project metadata. The eligible project still runs and the capped project starts only after release.

Measurement: run the scratch control with one capped ticket, one short-lived owner without metadata, and one eligible project. Record the old single status read during the hold and the bounded exact match after release. Compare both named project-cap cases in the hosted Dotfiles suite.

Success: the control shows one safety hold, then the exact cap reason within five seconds, with zero premature starts. Both project-cap cases and all required hosted checks pass.

Pivot: any premature start, missing exact reason, observation beyond five seconds, or failed required check rejects the change. Keep the scheduler's conservative hold and the separate incomplete-identity test.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric. The observed failure was [Dotfiles CI job 135760865987](https://github.com/fyodoriv/dotfiles/actions/runs/44576243623/job/135760865987).

## Fixture contract

A queue status snapshot can reflect a held slot before its owner metadata is available. A short command can also release its owner metadata before the lock closes. Tests for project caps must wait for their specific reason, alongside their separate checks that one project can proceed and another stays queued. The fixture owns its scratch queue and releases only its own holders. This changes test observation only.

## Scratch control

Prediction commit `293d3012` preceded the control. One read during the simulated metadata gap showed the safety hold. After the gap closed, the exact cap reason returned in 0.29 seconds. Beta completed before alpha's slot was released. Alpha started only after release. This shows how a single read can miss the cap reason. The CI log does not identify which file lacked metadata in the original run.

# Wait for the local browser before attaching

## Prediction

- **Hypothesis:** A PATH command can attach to a ready local browser after an initial refusal and return a clear error when none of the configured attempts succeeds.
- **Measurement:** Run `bats tests/browser-connect.bats` in hosted CI. Substitute fake curl and agent-browser commands. Check which local port was probed, how often the probe ran, and how often attach ran.
- **Success:** A delayed result probes twice and attaches once to a named, pinned session. Three failed probes attach zero times. Invalid settings and missing sessions also attach zero times. The direct command and Dotfiles action both find the same helper.
- **Pivot:** If 1 failed case starts an attach, opens a new browser, or probes an address other than loopback, keep the helper in review.
- **Anchor:** [Dotfiles issue 867](https://github.com/fyodoriv/dotfiles/issues/867) and the existing managed Chrome probe in `bin/agent-browser-singleton-preflight`.

Keep the port and attempt count in the Dotfiles settings table. Leave an
isolated browser under its existing lease. The hosted fixtures use no live
browser, profile, or network.

## Baseline

[Hosted test job](https://github.com/fyodoriv/dotfiles/actions/runs/46097508876/job/140832164281)
ran all four cases. The missing PATH command returned exit 127 in each
case. They expected the normal attach, exhaustion, invalid settings, and
help results. The new helper uses the existing browser client for attach.

The first candidate passed all four browser cases. The full gate also checks
the CLI reference, initial settings and the content-free command name. The
configuration template reads both defaults from the settings table with
[include](https://www.chezmoi.io/reference/templates/functions/include/) and
[fromYaml](https://www.chezmoi.io/reference/templates/functions/fromYaml/).

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

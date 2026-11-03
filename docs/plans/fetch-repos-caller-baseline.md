# Parallel fetch caller baseline

The Dotfiles tooling checkup inventory has four routing fixtures for
[Agentbrew #692](https://github.com/fyodoriv/agentbrew/issues/692). They
exercise the actual inventory script with local Git and GitHub stand-ins.
The fixtures cover two eligible checkouts, no-fetch mode, a failed first
fetch, and exclusion of linked worktrees and plain directories.

Run `JOBS=1 heavy-run bats tests/tooling-checkup-skill.bats`. The baseline
passed all four registered routing cases. They attempted five intercepted fetches,
reported one warning for the failed checkout, and made zero off-fixture
calls. Four recorder controls reject incomplete receipts.

The fixtures measure caller routing. The native worker still needs
separate timeout, cleanup, and mutation checks before activation.

# Report update phase times and a dirty checkout accurately

**Hypothesis:** Update can identify the completed phases and report a dirty
checkout as advisory when it is the only doctor finding. Other failed
commands keep their nonzero exit status.

**Measurement:** Run `tests/bin-dotfiles-update.bats` on hosted CI with fake
phase commands. Check the doctor sync module in a disposable repo with a
changed file. Match each measured phase, its exit status, and the summary.

**Success:** A normal update reports 5 phase times. A dirty-only doctor
result exits zero. A genuine failed command still yields its original
nonzero status, and no test runs an owner package upgrade.

**Pivot:** If 1 genuine failure exits zero or the timing spans a phase
that did not run, keep the current exit behavior and correct the receipt.

**Anchor:** [Dotfiles issue 866](https://github.com/fyodoriv/dotfiles/issues/866)
and [the sync doctor check](https://github.com/fyodoriv/dotfiles/blob/06f775667093b26c682bf55465a17ed1dc3132f0/modules/sync/doctor.sh).

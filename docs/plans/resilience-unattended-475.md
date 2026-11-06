# Unattended resilience setup experiment

Issue #475 reports a setup hang from an agent shell. The exact command that
hung is not known. This experiment covers only App Store and package installer
calls when standard input is not a terminal.

- **Hypothesis (GQM):** In a synthetic missing-app run, an unattended setup
  makes zero installer or store-launch calls instead of one or more, and names
  the person's next step. A terminal run keeps its existing install path.
- **Measurement:** `heavy-run bats tests/resilience-setup.bats`.
- **Success:** Both missing- and present-app unattended controls make zero
  installer/store-launch calls and complete; the terminal install-path control
  passes, as do all existing controls.
- **Pivot:** Any installer/store launch in unattended controls, missing next
  step, changed terminal install path, or failing existing control rejects
  this approach.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric;
  Munafò et al. (2017), preregistration.

Synthetic controls cannot establish the cause of the earlier hang or prove
that unrelated commands in the wizard cannot hang. Other findings in #475
remain open.

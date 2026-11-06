# Managed agent Git guard parser health

Issue #470 reports a deployed guard whose adjacent parser helper was missing.
Its source hash matched, but an inert-document control was falsely refused.

Goal: make this dependency failure visible before the next guarded command.
Question: can the doctor detect missing or broken deployed helper links and
offer the existing installer without weakening the guard? Predict two of two
synthetic missing/broken cases become visible, and both become healthy after
the scratch installer restores them. Safe read, destructive refusal and inert
document controls retain their expected results.

Measurement: `heavy-run bats tests/agent-guard-doctor.bats
tests/agent-hooks-block-dangerous-git.bats`. First capture a failing doctor
control before implementation. Success requires both detection and repair
cases, unchanged guard controls, and no writes outside scratch. Any missed
broken link, unsafe permit or unexpected refusal rejects the approach.

Scope: inspect the managed hook path declared by this repo's Agentfile and
its adjacent helper. This does not prove a live agent registered that hook or
interpret arbitrary settings commands. An advisory offers the existing
installer; the doctor does not overwrite a possibly user-owned hook itself.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #470's before/after observation.

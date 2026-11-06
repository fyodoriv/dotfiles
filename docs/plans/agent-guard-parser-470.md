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

Before implementing, also register a fixed, read-only registration control:
at least one supported Claude Code or Codex settings file must declare the
exact managed path for the Bash PreToolUse event. Missing, malformed or
unsupported command forms stay unverified. The checker reads JSON as data;
it never evaluates a settings command. This proves only the recognized
registration, not every agent or project override.

Inspect the managed hook path declared by this repo's Agentfile and its
adjacent helper. An advisory offers the existing installer; the doctor does
not overwrite a possibly user-owned hook itself. Before and after repair,
the scratch fixture checks a safe read and destructive refusal. Its inert
document is conservatively refused without the parser and accepted after
repair. Include a broken hook link and the full existing guard regression
file `tests/agent-hooks-block-dangerous-git-merged.bats` in qualification.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #470's before/after observation.

Before adding further controls, register three false-success cases: a root
`disableAllHooks: true`, a substituted executable guard, and a substituted
readable parser must each report warn. A recognized enabled registration with
source-identical deployed files must report pass. Also reject explicit hook
conditions or disable markers as unverified. Measure with `heavy-run bats
tests/agent-guard-doctor.bats`: success is 3/3 warnings and the existing
healthy control passing; any false pass rejects the approach. Compare bytes
with the local managed source without executing configured commands. This
does not establish effective policy for every agent or project override.

# Noninteractive secure completion startup

Issue #479 reports an insecure completion directory causing an interactive
prompt and consuming the first typed key. This is one reported incident, not
a measured population rate.

Goal: let the shell start without trusting insecure completion directories.
Question: can a synthetic insecure directory be skipped without a prompt,
while safe completion initialization remains available and the doctor points
to the audit? Metric: the old-dump synthetic control moves from one failed
startup to zero, with zero insecure fixture functions admitted and the safe
completion control retained.

Measurement: `heavy-run bats tests/zsh-completion-security.bats`. First capture
the failing startup control before changing the completion setup. Success
requires all controls, including doctor audit guidance, to pass. Any prompt,
insecure function admission, lost safe completion or misleading doctor result
rejects the approach; do not use `compinit -u` or change ownership silently.

The cached-dump path also needs the security audit: `compinit -C` skips it.
Before changing that path, predict that a current-dump control rejects the
same insecure fixture while retaining safe completion. Both old and current
dump controls must pass; an insecure path in either rejects the approach.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; the reported first-key loss in #479.

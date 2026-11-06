# GitHub admin scope default

Issue #475 reports that doctor asks for repository deletion and public-key
administration permissions even when those powers are not needed. The existing
`gh_admin_scopes` option can opt in, but its owner-machine default is true.

Goal: require only the ordinary scopes by default. Question: can the default
require zero of the two sensitive admin scopes while an explicit opt-in still
requires both? Predict the default moves from two to zero, the opt-in remains
two, and the existing ordinary scope checks remain unchanged.

Measurement: `heavy-run bats tests/gh-admin-scopes.bats
tests/dotfiles-config.bats`. Capture a failing default control before changing
the template, setting table and doctor fallback. Success requires both default
and opt-in controls and the configuration parity suite. Any admin scope in the
default, lost explicit opt-in or unrelated scope change rejects the approach.
Existing explicit machine settings are not changed.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et
al. (2017), preregistration; issue #475's scope report.

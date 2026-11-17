# Classify escaped dots inside SSH hosts

- Hypothesis: a regex for a public SSH host passes, and a private SSH host still fails.
- Measurement: hosted Bats cases in `tests/gh-wrapper-leak-guard.bats`.
- Success: zero hits for the four public hosts in plain and escaped form, and one hit for the synthetic private host in each form.
- Pivot: discard the parser change if any existing private-host case passes the guard.
- Anchor: the pre-push refusal linked to Dotfiles PR #562.

Read the complete host before comparing against the existing public host list. Keep all other scanner rules.

## Why needed

<one-paragraph explanation of motivation>

## What changed

<bullet list of substantive deltas; group by module (modules/X/doctor.sh, bin/Y, home/Z) or by lifecycle script>

## How to test manually

```bash
make lint                      # shellcheck (the only local gate for agents)
make lint-tasks                # TASKS.md only
# Tests run on hosted CI: push, then gh run watch <run-id> --exit-status (docs/ci-setup.md)
~/apps/tooling/dotfiles/bin/dotfiles-doctor   # doctor checks
```

## Privacy & security

<one or more lines describing what touches `lib/oss-readiness.sh`, the git hooks' privacy gates, secret patterns, or configured private identifiers; or
 `no new identifiers / secrets / privacy-gate changes; SECURITY.md guardrails reviewed`>

## Rollback

```bash
git revert <merge-commit>
```

<one line on revert safety; mention if `chezmoi apply` needs to re-run>

## Linked

- Ticket: PROJ-XXX (if applicable)

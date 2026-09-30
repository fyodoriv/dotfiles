<!-- The pr-vision-trace CI gate parses this file's structure — keep the
section headers and bullet shapes intact. -->

## Why needed

<one-paragraph explanation of motivation>

## What changed

<bullet list of substantive deltas; group by module (modules/X/doctor.sh, bin/Y, home/Z) or by lifecycle script>

## Vision trace

- **Vision goal**: <e.g. "Self-healing > documented manual steps" (VISION.md), capability tracker row from ROADMAP.md, or `N/A — <reason ≥3 chars>`>
- **User story**: <e.g. "docs/user-stories/05-config-heals-itself.md" or `N/A — <reason ≥3 chars>`>
- **Competitor prior art**: <e.g. other dotfiles frameworks (Homebrew Bundle, dotbot, yadm, …); or `N/A — repo doesn't have a competitive corpus`>

<!--
  Opt-out for non-substantive auto-commits (sync: auto-update, dependabot, lockfile bumps):
  <!-- vision-trace: not-applicable — <reason ≥3 chars> -->
-->

## How to test manually

```bash
make check                     # full gate (shellcheck + tasks-md lint + bats tests)
# OR targeted:
make lint                      # shellcheck only
make lint-tasks                # TASKS.md only
bats tests/<spec>.bats         # specific test file
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

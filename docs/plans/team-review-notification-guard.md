# Check review recipients before publishing

GitHub can ask code owners to review a pull request when it opens or leaves
draft. Removing a request later cannot prevent the first notification.

- **Hypothesis**: Checking the effective base-branch rules before a PR opens
  or leaves draft gives the right decision for four cases: a named person
  with no automatic team, a matching team, an unknown rule, and a team
  already requested by GitHub.
- **Measurement**: Run `bats tests/ship-it-self-review.bats` in CI. Read the
  workflow against the four cases in `commands/evals/ship-it.evals.json`.
- **Success**: Four correct decisions and zero manual team requests, review
  removals, or repository setting changes.
- **Pivot**: If any case requires guessing a rule or recipient, keep the PR
  in draft and report the decision that needs verification.
- **Anchor**: [GitHub code owners and draft
  requests](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)
  and [team assignment
  settings](https://docs.github.com/en/organizations/organizing-members-into-teams/managing-code-review-settings-for-your-team).

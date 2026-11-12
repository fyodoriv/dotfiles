# Help with a stale fetch: prediction

The update probe can return 1 when its last fetch is old and the local branch
is ahead of its remote. With `set -e`, `dotfiles --help` then exits before it
prints usage. A scratch fixture reproduced exit 1 and no usage text; the
observed full-check failure had the same symptom but did not capture output,
so its exact cause remains unconfirmed.

- **Hypothesis:** returning success after the optional update probe lets help
  work in the stale-fetch and ahead-branch case without changing update hints.
- **Measurement:** a controlled stale-fetch fixture in `tests/cli.bats`, its
  existing CLI tests, and `heavy-run make check`.
- **Success:** the planted fixture changes from exit 1/no usage to exit 0/usage;
  100% of the affected tests pass and update hints remain unchanged.
- **Pivot:** any incorrect hint, failed help case, or unintended fetch behavior
  stops the fix; isolate the update probe instead of changing its semantics.
- **Anchor:** Basili, Caldiera and Rombach 1994 (GQM); Munafò et al. 2017
  (pre-registration).

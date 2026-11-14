# Hosted performance queue prediction

The hosted hook trial reported that `heavy-run` was not on PATH, so its
performance measurements did not use the required exclusive queue.

- **Hypothesis:** Adding the checkout's `bin` to the test job PATH makes the
  existing performance gate use the same exclusive admission tool as other
  timing runs, without changing the gate command or its thresholds.
- **Measurement:** Hosted CI checks the workflow wiring and runs `make check`.
  Inspect its performance-gate output and the workflow contract tests.
- **Success:** The checkout's `heavy-run` is available before the gate; zero
  missing-queue warnings occur; the workflow contract and full gate pass.
- **Pivot:** A missing tool, warning, test failure or changed gate behavior
  keeps the result unqualified until the cause is fixed.
- **Anchor:** [hosted run 43623313574](https://github.com/fyodoriv/dotfiles/actions/runs/43623313574)
  and the repository's exclusive timing rule.

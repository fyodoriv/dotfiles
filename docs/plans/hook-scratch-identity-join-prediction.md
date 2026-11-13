# Scratch selection and identity join prediction

Register before implementing or running the join. The seven prior scratch
selection controls are not evidence of a live hook's selected bytes.

- **Hypothesis:** A scratch-only join can reject mismatches between the
  observed configured-root category and independently retained root identity
  and helper bytes at both boundaries.
- **Measurement:** Run `heavy-run bats tests/hook-scratch-selection.bats` and
  `heavy-run python3 tests/hook_effective_helper_test.py` after
  adding the fixture join. Use only fixture-owned paths and private scratch
  receipts; do not execute a live hook or signal a process.
- **Success:** The configured-root control joins only when its independent
  root `(dev, ino)` and expected helper bytes match before and after the
  scratch observation. Require the exact single configured receipt and equality
  of the complete pre/post snapshot tuples. Eight controls refuse changed bytes, absent
  helper, helper symlink, replaced root, replaced bin, wrong independent
  identity, fallback or unknown category, and a change after observation.
  Replace root and bin between the two boundaries for their respective cases.
  Uninstrumented fixture behavior remains equal in admitted cases and the
  outside canary remains unchanged. Results expose only closed categories.
- **Pivot:** Stop if any planted mismatch is accepted, boundary data is
  absent or ambiguous, an uninstrumented comparison changes, any outside write
  occurs, or a receipt leaks paths or content. Setup errors are inconclusive.
- **Anchor:** [Scratch selection prediction](hook-scratch-selection-prediction.md),
  [effective-input audit](hook-effective-input-audit.md), and
  `tests/helpers/hook_effective_helper.py`.

The expected root identity and helper bytes must come from an independent
fixture setup, not from the observation being checked. Use the existing
no-follow snapshot at both boundaries. Fall back or unknown stays
inconclusive. Independently review the fixture, mutation order, identity
binding, output and safety before execution. This is boundary correlation in
scratch data. It does not prove continuous immutability, which bytes Bash
actually read, live startup or interpreter closure, resistance to same-user
substitution, or recursive descendant completion. It does not qualify the
retained timing or RSS records.

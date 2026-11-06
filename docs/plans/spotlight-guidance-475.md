# Spotlight guidance experiment

Issue #475 asks the doctor to name who must act and the steps when a folder
remains indexed. The existing failure names Search Privacy but does not say to
add the folder or who must do it.

- **Hypothesis (GQM):** The indexed-folder fixture will report all four guidance
  elements (person, System Settings, Search Privacy, add the named folder), up
  from two of four, without changing the check or its repair.
- **Measurement:** `heavy-run bats tests/module-workflow.bats`.
- **Success:** All four elements appear in the indexed-folder failure and every
  existing workflow control passes.
- **Pivot:** Any missing element or any failed existing control abandons this
  description-only approach.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric; Apple's
  [Spotlight privacy steps](https://support.apple.com/en-euro/guide/mac-help/mchl1bb43b84/27/mac/27).

This covers only Spotlight guidance. The other findings in #475 remain open.

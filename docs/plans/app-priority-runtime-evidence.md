# Priority runtime evidence

Register before implementation. The installed command writes a timing record,
but that record does not say whether the native or shell path ran. A local
build also leaves an untracked Cargo target directory in the checkout.

- **Hypothesis:** An allowlisted runtime field identifies the selected path
  without recording commands, process data or other private information.
- **Measurement:** Hosted tests exercise native success, native failure,
  corrupt-artifact fallback, shell fallback and disabled stats. Check that a
  build target is ignored while source files remain tracked.
- **Success:** Each enabled run records exactly one `rust` or `shell` value;
  disabled stats record zero lines; zero unapproved values or payloads appear;
  build outputs are ignored and source changes remain visible.
- **Pivot:** A missing, duplicate or unexpected record retains the prior
  logging contract until corrected. A runtime tag proves path selection, not
  an in-use speedup.
- **Anchor:** `lib/stats.sh`, the native delivery plan, and the loaded
  app-priority LaunchAgent.

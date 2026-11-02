# Doctor correctness experiment

Goal: trust the reported repair result and run only a requested optional
module. Issues #412, #413, #416, and #418 define the observed failures.

The prediction was committed in TASKS.md as f60a71f before new tests ran.
The measurement is `bats tests/doctor-result-verification.bats
tests/doctor-optional-modules.bats tests/doctor-validate-overrides.bats
tests/doctor-overrides-snapshot.bats`. Keep the change only with zero failing
assertions and no false fixed result. Pivot to per-check handling if a false
fixed result or cross-plugin execution remains.

1. Reproduce no-op repairs reported fixed. Verify the original check after
   each successful command, symlink, managed-file, or defaults repair.
2. Reproduce valid local-AI overrides rejected when the module is off.
   Set list mode only for the lifecycle of check-ID discovery.
3. Reproduce plugin modules absent from `--module` lookup. Resolve verified
   plugin modules and dispatch through the existing sandbox. Reject ambiguous
   short names and support a qualified name. Keep core names first.
4. Integrate per-machine skips from #415 into the existing process-scoped
   snapshot. Keep shared overrides readable, validate both files, and run
   the skip test through the real CLI. The signature fixture puts its fake
   opencode first on PATH so it cannot inspect the host installation.
5. Run targeted tests, the full `heavy-run make check` gate, and independent
   review. Preserve the existing process-scoped override cache.

Alternatives: interpret zero exit status as health (rejected: no-op repairs
prove this false); source plugin code in core (rejected: loses the sandbox);
run the entire doctor to check one plugin (rejected: performs unrelated work).

The GQM metric uses Basili, Caldiera, Rombach (1994); stability follows
Forsgren, Humble, Kim (2018).

Gate follow-up: the new per-machine skip path required existing Codex and
VS Code fixtures to assert the local file. The full gate also exposed a
shared-HOME brew-skip fixture and an inherited ignored alarm in a timer
fixture. Predictions for their isolation and multiline guard were committed
in companion commits 9ed2c71 and a7165ba before edits. See
[fixture isolation](doctor-gate-fixture-isolation.md). The original named
base failures from #406 (including the timing check) passed on the fresh run.

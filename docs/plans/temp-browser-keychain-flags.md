# Temporary-browser keychain isolation

## Registered experiment

The built-in `temp-browser` launcher starts Chrome with a fresh profile. Its
shared flag array lacks `--use-mock-keychain` and `--password-store=basic`.
A scratch home can otherwise cause a macOS keychain prompt. Both built-in
headed and headless launches need those flags before a real browser is used.

**Hypothesis (GQM):** adding the two flags to the shared launch array reduces
missing required flags from a predicted two to zero in each built-in mode.
Both modes must retain their current profile, port and visibility behavior.

**Measurement:** extend the existing fake-Chrome headless and fake-open headed
fixtures, then run this unchanged command before and after the source change:

```sh
JOBS=1 heavy-run bats tests/temp-browser.bats
```

Each affected fixture must report all missing flags before repair, then assert
both exact argument lines after repair. A fake open process starts only the
fixture shell loop. No real Chrome, keychain, owner browser or setting is used.

**Success:** zero missing flags in both modes and every existing temporary
browser fixture passes. Keep the same fake executable controls before and
after. The required repository gate must also pass:

```sh
PATH="/opt/homebrew/opt/rust/bin:$PATH" JOBS=1 heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

**Pivot:** any missing flag, profile/port regression, visibility change, real
browser invocation or failing gate rejects this candidate. Revisit the shared
launch boundary; do not waive a mode or use a live launch as the first control.

**Anchor:** Basili, Caldiera and Rombach (1994), Goal-Question-Metric;
Munafò et al. (2017), preregistration; the owner's browser-launch keychain
isolation rule and its recorded scratch-home failure.

## Scope and lifecycle

Change only built-in launch arguments, their existing fixtures and browser
policy guidance. The disposable profile remains acquire/release scoped and
is deleted by the existing release path. Caller-provided launch hooks keep
their current protocol and must supply equivalent isolation themselves.
No authentication, browser launch, profile reuse, focus change or queue-slot
change is authorized by this experiment. This preparation does not revoke
any GitHub credential or prove a live sign-in flow.

Agent artifact test exemption: this initial commit records the experiment
only; it changes no launcher or deployed instruction. Whitespace validation
is the existing gate for this registration. Source validation follows the
registered failing fixture, then the fixed fixture and required gate.

# Optional app adoption

Goal: an existing foreign-owned app must not prevent unrelated apply steps
when Homebrew tries to adopt it without a terminal. Prediction committed in
678682b before the real rendered-script regression tests.

1. Render the actual Brew script in scratch HOME with fake Homebrew metadata
   and an app whose reported owner differs. Reproduce its bundle failure and
   the missing later-step marker.
2. Reuse Homebrew JSON app-artifact metadata. Consider only unregistered
   casks named in the temporary manifest with a real existing app directory.
   Compare its numeric owner with the current user. Do not use a broad
   require-admin flag or skip an already registered cask.
3. Omit only the conflicting cask from that invocation's temporary Brewfile,
   print its manual adoption command, and avoid an all-up-to-date claim.
   Leave other bundle errors fatal. No persistent setting or app is changed.
4. Test same-owner, registered root-owned, absent app, package-only metadata,
   unavailable metadata, and unrelated bundle errors through the actual
   rendered script. Measurement: `bats tests/brew-cask-adoption.bats`.
5. Require zero failures, independent review, and the full integration gate
   before committing source. A swallowed unrelated error or incorrect skip
   abandons preflight filtering in favor of a separately measured split.

Swallowing brew-bundle failures was rejected because it also hides missing
core formulas. Writing brew_skip automatically was rejected because it
changes user intent. Metadata and deferred-token files belong to one script
invocation and are deleted on exit. No install or permission change runs in
tests. Anchor: Basili, Caldiera, Rombach (1994), GQM; Forsgren, Humble, Kim
(2018), stability.

Use only an absolute artifact target supplied by Homebrew metadata. Missing
targets leave the bundle unchanged; guessing /Applications can conflict with
a configured app directory. This guard does not promise every Homebrew
version supplies the current target field.
